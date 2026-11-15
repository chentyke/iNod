import Foundation
import NodeSeekCore
import Observation
import WebKit

@MainActor
@Observable
public final class AccountSession {
    public enum SignInStatus {
        case unconfirmed, signedOut, signedIn
    }

    public private(set) var user: SignedInUser?
    public private(set) var revision = 0
    public private(set) var hasLoaded = false
    public private(set) var isRefreshing = false
    public private(set) var error: String?
    public private(set) var isSigningOut = false
    public private(set) var avatarRevision = 0
    @ObservationIgnored var isSyncingNodeImageKey = false
    public let website: SiteDataStore
    public let inbox: InboxService
    public let collections: CollectionsService
    public let categories: CategoryStore
    public let nodeImageHistory = NodeImageHistory()
    private let loadAuthentication: @MainActor (Bool) async throws -> AuthenticationSnapshot
    private var refreshTask: (revision: Int, task: Task<Void, Never>)?

    public convenience init() {
        let website = SiteDataStore()
        self.init(website: website, loadAuthentication: { try await website.bootstrap(force: $0) })
    }

    #if DEBUG
    private struct UITestWebsite: Decodable {
        let authentication: AuthenticationSnapshot
        let responses: [String: Data]
    }

    public static func fixtureForUITests(_ json: String) throws -> AccountSession {
        let fixture = try JSONDecoder().decode(UITestWebsite.self, from: Data(json.utf8))
        let website = SiteDataStore(persistsResponses: false) { fixture.authentication }
        website.responsesForUITests = fixture.responses
        return AccountSession(website: website, loadAuthentication: { try await website.bootstrap(force: $0) })
    }

    public static func offlineForUITests() -> AccountSession {
        let website = SiteDataStore(persistsResponses: false) { throw URLError(.notConnectedToInternet) }
        return AccountSession(website: website, loadAuthentication: { try await website.bootstrap(force: $0) })
    }
    #endif

    init(website: SiteDataStore, loadAuthentication: @escaping @MainActor (Bool) async throws -> AuthenticationSnapshot) {
        self.website = website
        self.loadAuthentication = loadAuthentication
        inbox = InboxService(website: website)
        collections = CollectionsService { userID, postID, collected in
            try await website.setCollected(collected, postID: postID, userID: userID)
        }
        categories = CategoryStore(website: website)
    }

    public var isLoggedIn: Bool { user != nil }

    public var signInStatus: SignInStatus {
        guard hasLoaded, !isSigningOut else { return .unconfirmed }
        return isLoggedIn ? .signedIn : .signedOut
    }

    private func observe(_ snapshot: AuthenticationSnapshot?, expectedRevision: Int) {
        guard expectedRevision == revision, let snapshot, snapshot.ready else { return }
        if user?.id != snapshot.user?.id {
            revision += 1
            inbox.reset(userID: snapshot.user?.id, unreadCount: snapshot.user?.unreadCount ?? 0)
            collections.reset(userID: snapshot.user?.id)
            categories.reset()
            nodeImageHistory.reset()
        }
        user = snapshot.user
        website.observe(snapshot)
        hasLoaded = true
        error = nil
    }

    public func synchronizeAfterRequest(expectedRevision: Int) {
        guard !isSigningOut else { return }
        observe(website.reader.authentication, expectedRevision: expectedRevision)
    }

    public func synchronize(from page: WebPage) async {
        guard !isSigningOut else { return }
        let version = revision
        if let snapshot = try? await SitePage.authentication(from: page), !isSigningOut {
            observe(snapshot, expectedRevision: version)
        }
    }

    public func refresh(force: Bool = false) async {
        guard !isSigningOut else { return }
        if let refreshTask { await refreshTask.task.value; return }
        let version = revision
        isRefreshing = true
        let task = Task { @MainActor in
            do {
                let snapshot = try await loadAuthentication(force)
                observe(snapshot, expectedRevision: version)
            } catch is CancellationError {
            } catch {
                if revision == version { self.error = SiteError.displayMessage(for: error) }
            }
        }
        refreshTask = (version, task)
        await task.value
        if refreshTask?.revision == version {
            refreshTask = nil
            isRefreshing = false
        }
    }

    public func updateCoins(_ coins: Int?) {
        if let coins { user?.coins = coins }
    }

    public func confirmSignedIn() async throws -> Bool {
        try await confirmedUser() != nil
    }

    public func withConfirmedSignIn(onSignedOut: () -> Void, perform: (SignedInUser) async throws -> Void) async throws {
        if let user = try await confirmedUser() {
            try Task.checkCancellation()
            guard signInStatus == .signedIn, self.user?.id == user.id else { throw CancellationError() }
            try await perform(user)
        } else {
            try Task.checkCancellation()
            guard signInStatus == .signedOut else { throw CancellationError() }
            onSignedOut()
        }
    }

    private func confirmedUser() async throws -> SignedInUser? {
        try Task.checkCancellation()
        if isSigningOut { throw CancellationError() }
        if !hasLoaded { await refresh(force: true) }
        try Task.checkCancellation()
        if isSigningOut { throw CancellationError() }
        guard hasLoaded else { throw SiteError.message(error ?? "无法确认登录状态，请重试。") }
        return user
    }

    public func avatarDidChange() { avatarRevision = Int(Date.now.timeIntervalSince1970 * 1000) }

    public func versionedAvatarURL(_ url: URL) -> URL {
        guard let user, url.path == user.avatarURL.path, avatarRevision > 0 else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "v", value: String(avatarRevision))]
        return components?.url ?? url
    }

    public func didSignIn() async {
        resetSession()
        await refresh(force: true)
    }

    public func signOut() async throws {
        guard !isSigningOut, let user else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        if let refreshTask { await refreshTask.task.value }
        _ = try await website.reader.accountAction(path: "/api/account/signOut", body: [:], userID: user.id, headers: ["x-csrf-challenge":"simple-token"])
        resetSession()
        let snapshot = try await website.bootstrap(force: true)
        observe(snapshot, expectedRevision: revision)
        guard snapshot.user == nil else { throw SiteError.message("官网仍显示登录状态，请稍后重试。") }
    }

    private func resetSession() {
        refreshTask?.task.cancel()
        refreshTask = nil
        isRefreshing = false
        revision += 1
        user = nil
        hasLoaded = false
        error = nil
        inbox.reset(userID: nil, unreadCount: 0)
        collections.reset(userID: nil)
        categories.reset()
        nodeImageHistory.reset()
        website.resetAuthentication()
    }
}
