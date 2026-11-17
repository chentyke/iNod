import NodeSeekCore
import Foundation

@MainActor
public final class SiteDataStore {
    let reader: SiteReader
    #if DEBUG
    var responsesForUITests: [String: Data]?
    #endif
    private let loadAuthentication: @MainActor () async throws -> AuthenticationSnapshot
    private var cache = ResponseCache<SiteRequestKey>()
    /// Feed and thread pages from earlier launches, shown while fresh ones load.
    private let disk: PersistentResponseStore?
    private static let persistedKinds: Set<String> = ["feed", "thread"]
    private static let accountDefaultsKey = "SiteDataStore.persistedAccount"
    @MainActor
    private final class DecodedResponse {
        let data: Data
        let value: Any

        init<Value>(_ value: Value, data: Data) {
            self.data = data
            self.value = value
        }
    }

    private var requests: [SiteRequestKey: (id: UUID, task: Task<DecodedResponse, Error>)] = [:]
    private var bootstrapTask: (id: UUID, task: Task<AuthenticationSnapshot, Error>)?
    private var snapshot: AuthenticationSnapshot?
    private var bootstrapDate: Date?
    private var generation = 0
    private var identityRevision = 0

    init(
        persistsResponses: Bool = true,
        loadAuthentication: (@MainActor () async throws -> AuthenticationSnapshot)? = nil
    ) {
        let reader = SiteReader(filtersBackgroundResources: true)
        self.reader = reader
        self.loadAuthentication = loadAuthentication ?? { try await reader.account() }
        disk = persistsResponses ? PersistentResponseStore() : nil
    }

    public var needsWebsite: Bool { reader.needsWebsite }

    func bootstrap(force: Bool = false) async throws -> AuthenticationSnapshot {
        if let bootstrapTask { return try await bootstrapTask.task.value }
        if !force, let snapshot, let bootstrapDate, Date.now.timeIntervalSince(bootstrapDate) < 60 { return snapshot }
        let id = UUID()
        let epoch = generation
        let task = Task { @MainActor in
            let result = try await loadAuthentication()
            try Task.checkCancellation()
            guard generation == epoch else { throw CancellationError() }
            if snapshot?.user?.id != result.user?.id { identityDidChange() }
            snapshot = result
            persistAccount(result.user?.id)
            bootstrapDate = .now
            return result
        }
        bootstrapTask = (id, task)
        defer { if bootstrapTask?.id == id { bootstrapTask = nil } }
        return try await task.value
    }

    func observe(_ snapshot: AuthenticationSnapshot) {
        guard snapshot.ready else { return }
        if self.snapshot?.user?.id != snapshot.user?.id { identityDidChange() }
        self.snapshot = snapshot
        persistAccount(snapshot.user?.id)
        bootstrapDate = reader.authentication != nil && reader.authentication?.user?.id == snapshot.user?.id ? .now : nil
    }

    public func cached<Value: Decodable>(_ type: Value.Type = Value.self, key: SiteRequestKey, allowingStale: Bool = true) -> Value? {
        guard snapshot?.user?.id == key.userID else { return nil }
        if let data = cache.value(for: key, allowingStale: allowingStale) { return try? JSONDecoder().decode(type, from: data) }
        guard allowingStale, let disk, Self.persistedKinds.contains(key.kind) else { return nil }
        // Before the site confirms who is signed in, trust the account the saved pages belong to.
        let owner = snapshot == nil ? persistedAccount : key.userID
        guard let data = disk.data(kind: key.kind, path: key.path, owner: owner) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// The account saved pages belong to; 0 is stored for a guest.
    private var persistedAccount: Int? {
        let id = UserDefaults.standard.integer(forKey: Self.accountDefaultsKey)
        return id == 0 ? nil : id
    }

    /// Saved pages belong to one account; a different account starts with none.
    private func persistAccount(_ userID: Int?) {
        guard let disk else { return }
        let stored = UserDefaults.standard.object(forKey: Self.accountDefaultsKey) as? Int
        guard stored != (userID ?? 0) else { return }
        disk.removeAll()
        UserDefaults.standard.set(userID ?? 0, forKey: Self.accountDefaultsKey)
    }

    func requestKey(kind: String, path: String) -> SiteRequestKey {
        .init(userID: snapshot?.user?.id, kind: kind, path: path)
    }

    private func authenticationForRead() async throws -> AuthenticationSnapshot {
        // The app checks authentication on activation and in the foreground.
        // Opening a page can use the established session without another home-page request.
        if let snapshot, reader.authentication?.user?.id == snapshot.user?.id { return snapshot }
        return try await bootstrap()
    }

    public func account<Value: Decodable>(_ resource: AccountResource, userID: Int, force: Bool = false) async throws -> Value {
        let auth = try await authenticationForRead()
        guard auth.user?.id == userID else { throw SiteError.message("登录已变化，请返回「我的」重新打开。") }
        return try await value(key: key(for: resource, viewerID: userID), lifetime: resource.lifetime, force: force) {
            try await self.reader.accountData(resource, userID: userID)
        } validate: { (result: Value) in
            if case .conversation(let peerID) = resource {
                guard (result as? ConversationData)?.belongs(to: userID, peerID: peerID) == true else {
                    throw SiteError.message("返回的会话用户不一致，请重新打开私聊。")
                }
            }
        }
    }

    func json<Value: Decodable>(path: String, requiresLogin: Bool = false, force: Bool = false, lifetime: TimeInterval = 30, expectedUserID: Int? = nil) async throws -> Value {
        let auth = try await authenticationForRead()
        if let expectedUserID, auth.user?.id != expectedUserID { throw CancellationError() }
        if requiresLogin, auth.user == nil { throw SiteError.message("请先登录后再打开。") }
        return try await value(key: .init(userID: auth.user?.id, kind: "json", path: path), lifetime: lifetime, force: force) {
            try await self.reader.jsonData(path: path, userID: requiresLogin ? auth.user?.id : nil)
        }
    }

    func perform<Value: Decodable>(path: String, body: [String: Any]? = nil, userID: Int, headers: [String: String] = [:], changesData: Bool = true) async throws -> Value {
        let revision = identityRevision
        let auth = try await bootstrap()
        guard revision == identityRevision, auth.user?.id == userID else { throw CancellationError() }
        let result: Value = try await reader.json(path: path, method: "POST", body: body, userID: userID, headers: headers)
        guard revision == identityRevision else { throw CancellationError() }
        if changesData { invalidate(after: path) }
        return result
    }

    public func publicResource<Value: Decodable>(_ resource: AccountResource, force: Bool = false) async throws -> Value {
        guard resource.isPublic else { throw SiteError.invalidResponse }
        let auth = try await authenticationForRead()
        return try await value(key: key(for: resource, viewerID: auth.user?.id), lifetime: resource.lifetime, force: force) {
            try await self.reader.publicData(resource)
        }
    }

    public func thread(id: Int, page: Int, includeBlocked: Bool = false, force: Bool = false,
                       summary: PostSummary? = nil) async throws -> PostDetail {
        let auth = try await authenticationForRead()
        let key = threadKey(id: id, page: page, includeBlocked: includeBlocked, viewerID: auth.user?.id)
        do {
            return try await value(key: key, lifetime: 60, force: force) {
                let data = try await self.reader.threadData(id: id, page: page, includeBlocked: includeBlocked)
                try self.checkIdentity(auth)
                return data
            }
        } catch let error as PostAccessError {
            try Task.checkCancellation()
            removeCachedThread(id: id, for: key)
            throw error
        } catch SiteError.httpStatus(404) {
            try Task.checkCancellation()
            // The site can return a generic 404 to viewers who cannot read a listed thread.
            guard let summary, summary.id == id, let access = PostAccessError.forMissingPost(summary, authentication: auth) else {
                throw SiteError.httpStatus(404)
            }
            removeCachedThread(id: id, for: key)
            throw access
        }
    }

    private func removeCachedThread(id: Int, for request: SiteRequestKey) {
        let matchesThread: (SiteRequestKey) -> Bool = { key in
            key.userID == request.userID && key.kind.hasPrefix("thread")
                && URL(string: key.path)?.path.hasPrefix("/post-\(id)-") == true
        }
        invalidate { $0 != request && matchesThread($0) }
        cache.remove(request)
        disk?.remove { matchesThread(SiteRequestKey(userID: $0.owner, kind: $0.kind, path: $0.path)) }
    }

    public func feed(_ route: NodeSeekRoute,includeBlocked: Bool = false, force: Bool = false) async throws -> FeedPage {
        let auth = try await authenticationForRead()
        let key = feedKey(route, includeBlocked: includeBlocked, viewerID: auth.user?.id)
        return try await value(key: key, lifetime: 15, force: force) {
            let data = try await self.reader.feedData(route,includeBlocked:includeBlocked)
            try self.checkIdentity(auth)
            return data
        }
    }

    func document<Value: Decodable>(_ url: URL, extraction: String, force: Bool = false) async throws -> Value {
        let auth = try await authenticationForRead()
        return try await value(key: .init(userID: auth.user?.id, kind: "document", path: url.absoluteString), lifetime: 60, force: force) {
            let data = try await self.reader.documentData(url, extraction: extraction)
            try self.checkIdentity(auth)
            return data
        }
    }

    private func checkIdentity(_ expected: AuthenticationSnapshot) throws {
        guard reader.authentication?.user?.id == expected.user?.id else {
            invalidate()
            bootstrapDate = nil
            throw SiteError.message("登录账号已变化，请刷新页面。")
        }
    }

    func action(path: String, body: [String: Any], userID: Int, headers: [String: String], messagePeerID: Int? = nil) async throws -> ReactionResponse {
        let revision = identityRevision
        let auth = try await bootstrap()
        guard revision == identityRevision, auth.user?.id == userID else { throw CancellationError() }
        let result = try await reader.accountAction(path: path, body: body, userID: userID, headers: headers)
        guard revision == identityRevision else { throw CancellationError() }
        invalidate(after: path, messagePeerID: messagePeerID)
        return result
    }

    private func invalidate(after path: String, messagePeerID: Int? = nil) {
        if path.hasPrefix("/api/notification/message/") {
            let conversationPath = messagePeerID.map { AccountResource.conversation($0).path }
            invalidate { key in
                key.kind == "messages" || key.path == Self.unreadCountPath
                    || (key.kind == "conversation" && (conversationPath == nil || key.path == conversationPath))
            }
        } else if path.hasPrefix("/api/notification/") {
            let prefix = path.split(separator: "/").dropLast().joined(separator: "/")
            invalidate { $0.path.hasPrefix("/\(prefix)/") || $0.path == Self.unreadCountPath }
        } else if path.hasPrefix("/api/fans/") {
            invalidate { $0.kind == "profile" || $0.path.hasPrefix("/api/fans/") }
        } else if path.hasPrefix("/api/statistics/collection") {
            invalidate { $0.kind.hasPrefix("thread") || ["collections", "profile"].contains($0.kind) }
        } else if path.hasPrefix("/api/attendance") {
            invalidate { ["attendance", "credit", "profile"].contains($0.kind) || $0.path.hasPrefix("/api/progress/") }
        } else if path.hasPrefix("/api/content/") {
            invalidate { $0.kind.hasPrefix("feed") || $0.kind.hasPrefix("thread") || ["topics", "replies", "collections", "credit", "profile"].contains($0.kind) || $0.path.hasPrefix("/api/progress/") || $0.path.hasPrefix("/api/content/") }
        } else {
            invalidate()
        }
    }

    func invalidateThread(id: Int) {
        invalidate { key in
            (key.kind.hasPrefix("thread") && URL(string: key.path)?.path.hasPrefix("/post-\(id)-") == true)
                || ["credit", "profile"].contains(key.kind) || key.path.hasPrefix("/api/progress/")
        }
    }

    private func invalidate(matching shouldRemove: (SiteRequestKey) -> Bool) {
        cache.remove(where: shouldRemove)
        for key in requests.keys.filter(shouldRemove) {
            requests.removeValue(forKey: key)?.task.cancel()
        }
    }

    public func invalidate() {
        generation += 1
        cache.removeAll()
        for request in requests.values { request.task.cancel() }
        requests.removeAll()
    }

    private func identityDidChange() {
        identityRevision += 1
        invalidate()
    }

    func resetAuthentication() {
        identityDidChange()
        disk?.removeAll()
        bootstrapTask?.task.cancel()
        bootstrapTask = nil
        snapshot = nil
        bootstrapDate = nil
        reader.resetAuthentication()
    }

    private func value<Value: Decodable>(key: SiteRequestKey, lifetime: TimeInterval, force: Bool,
                                         fetch: @escaping @MainActor () async throws -> Data,
                                         validate: ((Value) throws -> Void)? = nil) async throws -> Value {
        #if DEBUG
        if let responsesForUITests {
            guard let data = responsesForUITests[key.path] else {
                throw SiteError.message("Missing UI test response for \(key.path)")
            }
            return try JSONDecoder().decode(Value.self, from: data)
        }
        #endif
        if !force, let data = cache.value(for: key) { return try JSONDecoder().decode(Value.self, from: data) }
        let epoch = generation
        let request: (id: UUID, task: Task<DecodedResponse, Error>)
        if let existing = requests[key] { request = existing }
        else {
            request = (UUID(), Task { @MainActor in
                let data = try await fetch()
                try Task.checkCancellation()
                guard self.generation == epoch else { throw CancellationError() }
                let value = try JSONDecoder().decode(Value.self, from: data)
                try validate?(value)
                let response = DecodedResponse(value, data: data)
                self.cache.insert(data, for: key, lifetime: lifetime)
                if Self.persistedKinds.contains(key.kind) { self.disk?.insert(data, kind: key.kind, path: key.path, owner: key.userID) }
                return response
            })
            requests[key] = request
        }
        defer { if requests[key]?.id == request.id { requests[key] = nil } }
        let response = try await request.task.value
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
        if let value = response.value as? Value { return value }
        let value = try JSONDecoder().decode(Value.self, from: response.data)
        try validate?(value)
        return value
    }
}
