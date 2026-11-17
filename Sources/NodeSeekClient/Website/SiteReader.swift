import NodeSeekCore
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class SiteReader {
    private let filtersBackgroundResources: Bool
    private var storedPage: WebPage?
    var page: WebPage {
        if let storedPage { return storedPage }
        let page = SitePage.make()
        storedPage = page
        return page
    }
    var needsWebsite = false
    private(set) var authentication: AuthenticationSnapshot?
    private var operationID = UUID()
    /// The address the page has just finished loading, until something reads it.
    /// The sign-in check loads the default feed, so the first feed request needn't fetch it again.
    private var loadedDocument: URL?
    private static let firstDocument = NodeSeekRoute.feed(category: "", sort: .replyTime, page: 1).url

    init(filtersBackgroundResources: Bool = false) {
        self.filtersBackgroundResources = filtersBackgroundResources
    }

    func resetAuthentication() {
        operationID = UUID()
        authentication = nil
        loadedDocument = nil
        storedPage = nil
        needsWebsite = false
    }

    func accountData(_ resource: AccountResource, userID: Int) async throws -> Data {
        try await prepareAccount(userID: userID)
        return try await readResource(resource, userID: userID)
    }

    func publicData(_ resource: AccountResource) async throws -> Data {
        guard resource.isPublic else { throw SiteError.invalidResponse }
        return try await readResource(resource, userID: authentication?.user?.id ?? 0)
    }

    private func readResource(_ resource: AccountResource, userID: Int) async throws -> Data {
        try await scriptData(AccountScripts.read, arguments: ["path": resource.path, "kind": resource.kind, "page": resource.page, "userID": userID, "memberID": resource.memberID ?? 0])
    }

    func json<Value: Decodable>(path: String, method: String = "GET", body: [String: Any]? = nil, userID: Int? = nil, headers: [String: String] = [:]) async throws -> Value {
        try JSONDecoder().decode(Value.self, from: await jsonData(path: path, method: method, body: body, userID: userID, headers: headers))
    }
    func jsonData(path: String, method: String = "GET", body: [String: Any]? = nil, userID: Int? = nil, headers: [String: String] = [:]) async throws -> Data {
        guard path.hasPrefix("/api/"), !path.hasPrefix("//") else { throw SiteError.invalidResponse }
        if let userID { try await prepareAccount(userID: userID) }
        else if page.url == nil { _ = try await account() }
        let encoded = try body.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys), as: UTF8.self) } ?? ""
        return try await scriptData(AccountScripts.request, arguments: ["path":path,"method":method,"body":encoded,"headers":headers])
    }

    func accountAction(path: String, body: [String: Any], userID: Int, headers: [String: String] = [:]) async throws -> ReactionResponse {
        try await prepareAccount(userID: userID)
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await accountDecode(AccountScripts.action, arguments: ["path": path, "body": body.isEmpty ? "" : String(decoding: data, as: UTF8.self), "headers": headers])
    }

    func uploadAvatar(_ data: Data, userID: Int) async throws {
        try await prepareAccount(userID: userID)
        _ = try await scriptData(AccountScripts.uploadAvatar,arguments:["encoded":data.base64EncodedString()])
    }

    func nodeImageGrant(userID: Int) async throws -> Data {
        try await prepareAccount(userID: userID)
        guard let url = page.url, url.scheme == "https", url.host() == NodeSeekRoute.origin.host() else {
            throw SiteError.invalidResponse
        }
        return try await scriptData(AccountScripts.request, arguments: [
            "path": "/api/cAuth?target=NodeImage", "method": "GET", "body": "", "headers": [String: String]()
        ])
    }

    private func prepareAccount(userID: Int) async throws {
        if page.url == nil || authentication?.user?.id != userID { _ = try await account() }
        try await requireLogin()
        guard authentication?.user?.id == userID else { throw SiteError.message("登录账号已变化，请返回「我的」重新打开。") }
    }

    private func accountDecode<T: Decodable>(_ script: String, arguments: [String: Any]) async throws -> T {
        try JSONDecoder().decode(T.self, from: await scriptData(script, arguments: arguments))
    }

    private func scriptData(_ script: String, arguments: [String: Any] = [:]) async throws -> Data {
        try checkedScriptData(await runScript(script, arguments: arguments))
    }

    private func runScript(_ script: String, arguments: [String: Any] = [:]) async throws -> Any? {
        let boundedScript = #"""
        const fetch = async (url, options = {}) => {
            try { return await globalThis.fetch(url, {...options,signal:AbortSignal.timeout(\#(Int(Self.requestTimeout * 1000)))}); }
            catch(e) {
                if (e.name === 'TimeoutError' || e.name === 'AbortError') throw new Error('\#(ScriptNetworkError.timedOut)');
                if (e instanceof TypeError) throw new Error(navigator.onLine === false ? '\#(ScriptNetworkError.offline)' : '\#(ScriptNetworkError.unreachable)');
                throw e;
            }
        };
        try {
        """# + script + #"""
        } catch(e) { return JSON.stringify({__error:e.message||String(e)}); }
        """#
        let requestPage = page
        let result = try await requestPage.callJavaScript(boundedScript, arguments: arguments)
        guard requestPage === storedPage else { throw CancellationError() }
        return result
    }

    private func checkedScriptData(_ result: Any?) throws -> Data {
        guard let json = result as? String else { throw SiteError.invalidResponse }
        let data = Data(json.utf8)
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            switch object["__postAccess"] as? String {
            case "level": throw PostAccessError.levelRequired(object["rank"] as? Int)
            case "signIn": throw PostAccessError.signInRequired
            case "private": throw PostAccessError.privatePost
            default: break
            }
            if let message = object["__error"] as? String {
                if let networkError = ScriptNetworkError.urlError(for: message) { throw networkError }
                if object["__needsWebsite"] as? Bool == true {
                    needsWebsite = true
                    // A challenge page or a bare 403. A 403 that carries the site's own words keeps them.
                    if object["__status"] != nil || message.hasSuffix("(403)") || message.contains("需要完成验证") {
                        throw SiteError.verificationRequired
                    }
                }
                if let status = object["__status"] as? Int { throw SiteError.httpStatus(status) }
                throw SiteError.message(message)
            }
        }
        return data
    }

    func account() async throws -> AuthenticationSnapshot {
        if storedPage?.url?.host() == NodeSeekRoute.home.url.host(), authentication != nil {
            _ = try await documentData(NodeSeekRoute.home.url, extraction: SiteScripts.readiness)
        } else {
            let operation = UUID()
            operationID = operation
            let rules = filtersBackgroundResources ? await SitePage.backgroundReaderRules() : nil
            try Task.checkCancellation()
            guard operationID == operation else { throw CancellationError() }
            if filtersBackgroundResources { storedPage = SitePage.make(contentRules: rules) }
            do {
                try await load(Self.firstDocument, operation: operation)
            } catch let error as SiteError {
                try Task.checkCancellation()
                guard operationID == operation else { throw CancellationError() }
                guard rules != nil, needsWebsite else { throw error }
                storedPage = SitePage.make()
                try await load(Self.firstDocument, operation: operation)
            }
        }
        guard let authentication else { throw SiteError.invalidResponse }
        return authentication
    }

    func chickenCost() async throws -> Int {
        try await requireLogin()
        let data = try await scriptData(SiteScripts.get, arguments: ["path": "/api/progress/today?scope=freelike"])
        let quota = try JSONDecoder().decode(FreeLikeQuota.self, from: data)
        guard quota.maxFreeLike >= 0, quota.freeLikeUsed >= 0 else { throw SiteError.invalidResponse }
        return quota.cost
    }

    func react(commentID: Int, reaction: CommentReaction, userID: Int) async throws -> ReactionResponse {
        try await prepareAccount(userID: userID)
        try Task.checkCancellation()
        let body = try JSONSerialization.data(withJSONObject: ["commentId": commentID, "action": "add"])
        let response: ReactionResponse = try await post(path: "/api/statistics/\(reaction.rawValue)", body: body)
        guard response.success else { throw SiteError.message(response.message ?? "操作未成功，请稍后重试。") }
        guard let count = response.current, count >= 0 else {
            throw SiteError.message("官网没有返回最新数量。请刷新帖子后检查结果，避免重复操作。")
        }
        return response
    }

    func feed(_ route: NodeSeekRoute) async throws -> FeedPage {
        try JSONDecoder().decode(FeedPage.self, from: await feedData(route))
    }

    func feedData(_ route: NodeSeekRoute,includeBlocked: Bool = false) async throws -> Data {
        try await documentData(route.url, extraction: SiteScripts.feed(includeBlocked: includeBlocked))
    }

    func thread(id: Int, page: Int) async throws -> PostDetail {
        try JSONDecoder().decode(PostDetail.self, from: await threadData(id: id, page: page))
    }

    func threadData(id: Int, page: Int,includeBlocked: Bool = false) async throws -> Data {
        try await documentData(
            NodeSeekRoute.thread(id: id, page: page).url,
            extraction: includeBlocked ? SiteScripts.thread.replacingOccurrences(of: ".filter(c => !c.blocked)", with: "") : SiteScripts.thread,
            checkingPostAccess: true
        )
    }

    func documentData(_ url: URL, extraction: String, checkingPostAccess: Bool = false) async throws -> Data {
        if page.url == nil || authentication == nil { _ = try await account() }
        needsWebsite = false
        if loadedDocument == url {
            loadedDocument = nil
            do { return try readDocument(await runScript(SiteScripts.loadedDocument(extraction))) }
            catch is CancellationError { throw CancellationError() }
            catch { }
            needsWebsite = false
        }
        return try readDocument(await runScript(
            SiteScripts.document(extraction, checkingPostAccess: checkingPostAccess), arguments: ["path": url.absoluteString]
        ))
    }

    private func readDocument(_ result: Any?) throws -> Data {
        guard let document = result as? [String: String],
              let content = document["content"], let auth = document["authentication"] else {
            _ = try checkedScriptData(result)
            throw SiteError.invalidResponse
        }
        let snapshot = try JSONDecoder().decode(AuthenticationSnapshot.self, from: Data(auth.utf8))
        guard snapshot.ready else { throw SiteError.invalidResponse }
        authentication = snapshot
        return Data(content.utf8)
    }

    func reply(postID: Int, content: String) async throws {
        try await requireLogin()
        let body = try JSONSerialization.data(withJSONObject: ["content": content, "mode": "new-comment", "postId": postID])
        let response: ReactionResponse = try await post(path: "/api/content/new-comment", body: body, token: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)))
        guard response.success else { throw SiteError.message(response.message ?? "回复未成功，请稍后重试。") }
    }

    private func requireLogin() async throws {
        let snapshot: AuthenticationSnapshot
        if let authentication { snapshot = authentication }
        else { snapshot = try await SitePage.authentication(from: page); authentication = snapshot }
        guard snapshot.ready, snapshot.user != nil else { throw SiteError.message("登录已过期，请在官网登录后重试。") }
    }

    private func post<T: Decodable>(path: String, body: Data, token: String = "") async throws -> T {
        let data = try await scriptData(SiteScripts.post, arguments: ["path": path, "body": String(decoding: body, as: UTF8.self), "token": token])
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func load(_ url: URL, operation: UUID) async throws {
        needsWebsite = false
        loadedDocument = nil
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            for try await event in page.load(request) {
                try Task.checkCancellation()
                guard operationID == operation else { throw CancellationError() }
                if event == .committed { break }
            }
        } catch WebPage.NavigationError.failedProvisionalNavigation(let underlying) {
            throw underlying
        }
        // Read as soon as the document is parsed; advertisements and images must not hold up the native feed.
        for _ in 0..<60 {
            try Task.checkCancellation()
            guard operationID == operation else { throw CancellationError() }
            if let snapshot = try? await SitePage.authentication(from: page), snapshot.ready {
                try Task.checkCancellation()
                guard operationID == operation else { throw CancellationError() }
                authentication = snapshot
                if page.url == url { loadedDocument = url }
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        needsWebsite = true
        throw SiteError.verificationRequired
    }

    /// How long a request may go without an answer before the reader is told. Long enough for a slow
    /// mobile network, short enough that a dead one doesn't leave a spinner running.
    static let requestTimeout: TimeInterval = 15
}

/// The page script's own words for a failed `fetch`, turned back into the URL errors they stand for.
enum ScriptNetworkError {
    static let timedOut = "连接超时，请检查网络后重试。"
    static let offline = "网络未连接，请检查网络设置后重试。"
    static let unreachable = "无法连接 NodeSeek，请检查网络后重试。"

    static func urlError(for message: String) -> URLError? {
        switch message {
        case timedOut: URLError(.timedOut)
        case offline: URLError(.notConnectedToInternet)
        case unreachable: URLError(.cannotConnectToHost)
        default: nil
        }
    }
}
