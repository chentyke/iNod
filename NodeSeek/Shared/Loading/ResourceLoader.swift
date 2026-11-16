import NodeSeekClient
import Foundation
import Observation

@MainActor @Observable
final class ResourceLoader<Value: Decodable> {
    var value: Value?
    var error: LoadFailure?
    private(set) var nextPageError: String?
    var loading = false
    private(set) var isLoadingFirstPage = false
    var updating = false
    private var key: SiteRequestKey?
    private var operation = UUID()
    @discardableResult
    func load(key: SiteRequestKey, cached: Value? = nil, appending merge: ((Value, Value) -> Value)? = nil, fetch: () async throws -> Value) async -> Value? {
        let previous = value
        if merge != nil {
            guard previous != nil, !loading, !updating else { return nil }
            guard self.key?.userID == key.userID else {
                value = nil
                error = LoadFailure(message: "登录账号已变化，请刷新页面。")
                return nil
            }
        } else {
            if self.key != key { value = nil }
            self.key = key
            if value == nil { value = cached }
        }
        let id = UUID(); operation = id
        loading = true; error = nil; nextPageError = nil
        isLoadingFirstPage = merge == nil
        defer {
            if id == operation {
                loading = false
                isLoadingFirstPage = false
            }
        }
        do {
            let result = try await fetch()
            try Task.checkCancellation()
            guard id == operation else { return nil }
            if let merge, let previous { value = merge(previous, result) }
            else { value = result }
            return result
        } catch {
            if id == operation, !Task.isCancelled, !(error is CancellationError) {
                if merge == nil { self.error = LoadFailure(error) }
                else { nextPageError = SiteError.displayMessage(for: error) }
            }
        }
        return nil
    }

    @discardableResult
    func load(_ website: SiteDataStore, _ resource: WebsiteResource, force: Bool = false, allowingStale: Bool = true, appending merge: ((Value, Value) -> Value)? = nil) async -> Value? {
        let key = website.key(for: resource)
        return await load(key: key, cached: merge == nil ? website.cached(key: key, allowingStale: allowingStale) : nil, appending: merge) {
            try await website.load(resource, force: force)
        }
    }

    func load(_ website: SiteDataStore, _ document: WebsiteDocument, force: Bool = false) async {
        let key = website.key(for: document)
        await load(key: key, cached: website.cached(key: key)) {
            try await website.load(document, force: force)
        }
    }
}
