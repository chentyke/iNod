import NodeSeekCore
import NodeSeekClient
import Foundation
import Observation

@MainActor
@Observable
final class AccountLoader<Value: Decodable> {
    var value: Value?
    var isLoading = false
    private(set) var isLoadingFirstPage = false
    var isUpdating = false
    var error: LoadFailure?
    private(set) var nextPageError: String?
    private var operationID = UUID()
    private var viewerID: Int?
    private var resource: AccountResource?

    @discardableResult
    func load(_ website: SiteDataStore, _ resource: AccountResource, userID: Int, force: Bool = false, appending merge: ((Value, Value) -> Value)? = nil) async -> Value? {
        await read(website, resource, viewerID: userID, force: force, publicly: false, merge: merge)
    }

    @discardableResult
    func loadPublic(_ website: SiteDataStore, _ resource: AccountResource, viewerID: Int?, force: Bool = false, appending merge: ((Value, Value) -> Value)? = nil) async -> Value? {
        await read(website, resource, viewerID: viewerID, force: force, publicly: true, merge: merge)
    }

    private func read(_ website: SiteDataStore, _ resource: AccountResource, viewerID: Int?, force: Bool, publicly: Bool, merge: ((Value, Value) -> Value)?) async -> Value? {
        let previous = value
        if merge != nil {
            guard previous != nil, self.viewerID == viewerID, !isLoading, !isUpdating else { return nil }
        } else {
            if self.resource != resource || self.viewerID != viewerID { value = nil }
            self.resource = resource
            self.viewerID = viewerID
            if value == nil {
                value = website.cached(key: website.key(for: resource, viewerID: viewerID))
            }
        }
        let operation = UUID()
        operationID = operation
        isLoading = true
        isLoadingFirstPage = merge == nil
        error = nil
        nextPageError = nil
        defer {
            if operationID == operation {
                isLoading = false
                isLoadingFirstPage = false
            }
        }
        do {
            let result: Value
            if publicly { result = try await website.publicResource(resource, force: force) }
            else if let viewerID { result = try await website.account(resource, userID: viewerID, force: force) }
            else { throw SiteError.message("请先登录后再打开。") }
            try Task.checkCancellation()
            guard operationID == operation else { return nil }
            if let merge, let previous { value = merge(previous, result) }
            else { value = result }
            return result
        } catch is CancellationError { }
        catch {
            if operationID == operation, !Task.isCancelled {
                if merge == nil { self.error = LoadFailure(error) }
                else { nextPageError = SiteError.displayMessage(for: error) }
            }
        }
        return nil
    }

    func action(_ website: SiteDataStore, _ action: WebsiteAction, userID: Int) async -> ReactionResponse? {
        guard !isUpdating else { return nil }
        isUpdating = true
        error = nil
        defer { isUpdating = false }
        do { return try await website.update(action, userID: userID) }
        catch { self.error = LoadFailure(error); return nil }
    }
}
