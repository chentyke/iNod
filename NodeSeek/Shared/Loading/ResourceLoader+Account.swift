import NodeSeekClient
import NodeSeekCore

extension ResourceLoader {
    @discardableResult
    func load(_ website: SiteDataStore, _ resource: AccountResource, userID: Int, force: Bool = false,
              appending merge: ((Value, Value) -> Value)? = nil) async -> Value? {
        let key = website.key(for: resource, viewerID: userID)
        return await load(key: key, cached: website.cached(key: key), appending: merge) {
            try await website.account(resource, userID: userID, force: force)
        }
    }

    @discardableResult
    func loadPublic(_ website: SiteDataStore, _ resource: AccountResource, viewerID: Int?, force: Bool = false,
                    appending merge: ((Value, Value) -> Value)? = nil) async -> Value? {
        let key = website.key(for: resource, viewerID: viewerID)
        return await load(key: key, cached: website.cached(key: key), appending: merge) {
            try await website.publicResource(resource, force: force)
        }
    }

    func action(_ website: SiteDataStore, _ action: WebsiteAction, userID: Int) async -> ReactionResponse? {
        guard !updating else { return nil }
        updating = true
        error = nil
        defer { updating = false }
        do { return try await website.update(action, userID: userID) }
        catch { self.error = LoadFailure(error); return nil }
    }
}
