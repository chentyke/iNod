import NodeSeekCore
import Foundation
import Observation

@MainActor @Observable
public final class CategoryStore {
    private static let path = "/api/content/list-categories"
    private static let lifetime: TimeInterval = 43_200
    private let website: SiteDataStore

    init(website: SiteDataStore) { self.website = website }
    public private(set) var items = ForumCategory.all
    public private(set) var error: String?
    private(set) var loading = false
    private var refreshedAt: Date?
    private var userID: Int?
    private var revision = 0

    func reset() {
        revision += 1
        items = ForumCategory.all
        refreshedAt = nil
        userID = nil
        loading = false
        error = nil
    }

    private var isFresh: Bool {
        guard let refreshedAt else { return false }
        return Date.now.timeIntervalSince(refreshedAt) < Self.lifetime
    }

    public func refresh(force: Bool = false) async {
        guard !loading else { return }
        let viewerID = website.requestKey(kind: "json", path: Self.path).userID
        if !force, userID == viewerID, isFresh { return }
        let version = revision
        loading = true
        defer { if revision == version { loading = false } }
        do {
            let auth = try await website.bootstrap()
            guard revision == version else { return }
            if userID != auth.user?.id { items = ForumCategory.all; refreshedAt = nil; userID = auth.user?.id }
            if !force, isFresh { return }
            let result: CategoryResponse = try await website.json(path: Self.path, force: force, lifetime: Self.lifetime)
            try Task.checkCancellation()
            guard revision == version else { return }
            guard result.success, !result.data.isEmpty, Set(result.data.map(\.id)).count == result.data.count else { throw SiteError.invalidResponse }
            items = [ForumCategory.all[0]] + result.data
            refreshedAt = .now
            error = nil
        } catch { if revision == version, !Task.isCancelled, !(error is CancellationError) { self.error = SiteError.displayMessage(for: error) } }
    }
}
