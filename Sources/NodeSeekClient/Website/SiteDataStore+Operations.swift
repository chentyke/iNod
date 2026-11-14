import Foundation
import NodeSeekCore

extension SiteDataStore {
    public func key(for resource: AccountResource, viewerID: Int?) -> SiteRequestKey {
        SiteRequestKey(userID: viewerID, kind: resource.kind, path: resource.path)
    }

    public func feedKey(_ route: NodeSeekRoute, includeBlocked: Bool, viewerID: Int?) -> SiteRequestKey {
        SiteRequestKey(userID: viewerID, kind: includeBlocked ? "feed-including-blocked" : "feed", path: route.url.absoluteString)
    }

    public func threadKey(id: Int, page: Int, includeBlocked: Bool, viewerID: Int?) -> SiteRequestKey {
        SiteRequestKey(userID: viewerID, kind: includeBlocked ? "thread-including-blocked" : "thread", path: NodeSeekRoute.thread(id: id, page: page).url.absoluteString)
    }

    public func key(for resource: WebsiteResource) -> SiteRequestKey { requestKey(kind: "json", path: resource.path) }

    public func key(for document: WebsiteDocument) -> SiteRequestKey { requestKey(kind: "document", path: document.url.absoluteString) }

    public func load<Value: Decodable>(_ resource: WebsiteResource, force: Bool = false) async throws -> Value {
        try await json(path: resource.path, requiresLogin: resource.requiresLogin, force: force)
    }

    public func load<Value: Decodable>(_ document: WebsiteDocument, force: Bool = false) async throws -> Value {
        try await self.document(document.url, extraction: document.extraction, force: force)
    }

    public func perform<Value: Decodable>(_ action: WebsiteAction, userID: Int) async throws -> Value {
        let request = action.request
        return try await perform(path: request.path, body: request.body.isEmpty ? nil : request.body,
                                 userID: userID, headers: request.headers, changesData: request.changesData)
    }

    public func update(_ action: WebsiteAction, userID: Int) async throws -> ReactionResponse {
        let request = action.request
        return try await self.action(path: request.path, body: request.body, userID: userID, headers: request.headers)
    }

    public func telegramBinding(userID: Int) async throws -> (bound: Bool, detail: TelegramAccount?) {
        let status: TelegramBindingStatus = try await document(NodeSeekRoute.origin.appending(path: "setting"), extraction: #"""
        const user=window.__config__?.user;
        if(!user)throw new Error('请先登录。');
        return JSON.stringify({userID:Number(user.member_id),bound:user.telegram_id!==null&&user.telegram_id!==undefined&&String(user.telegram_id)!==''});
        """#, force: true)
        guard status.userID == userID else { throw SiteError.message("登录账号已变化，请重新打开设置。") }
        let response: TelegramAccountResponse? = status.bound ? try await json(path: "/api/account/telegram", requiresLogin: true, force: true, expectedUserID: userID) : nil
        return (status.bound, response?.telegramDetail)
    }

    public func createVote(title: String, multiple: Bool, isPublic: Bool, options: [String], userID: Int) async throws -> Int {
        let response: CreatedVoteResponse = try await perform(.createVote(title: title, multiple: multiple, isPublic: isPublic, options: options), userID: userID)
        return response.vote.id
    }

    public func festiveStyle(userID: Int) async throws -> Bool {
        let response: WebsitePreferenceResponse = try await perform(.readWebsitePreferences, userID: userID)
        return response.data.enable_festivous_style ?? false
    }

    public func websiteStyle(userID: Int) async throws -> String {
        let response: WebsiteStyleResponse = try await json(path: "/api/style", requiresLogin: true, expectedUserID: userID)
        return response.data ?? ""
    }

    public func prepareTransfer(recipientID: Int, userID: Int) async throws -> String {
        let response: TransferPreparation = try await perform(.prepareTransfer(recipientID: recipientID), userID: userID)
        return response.receiver_name
    }

    func setCollected(_ collected: Bool, postID: Int, userID: Int) async throws {
        _ = try await action(path: "/api/statistics/collection",
                             body: ["postId": postID, "action": collected ? "add" : "remove"], userID: userID, headers: [:])
    }

    public func uploadAvatar(_ data: Data, userID: Int) async throws {
        _ = try await bootstrap()
        try await reader.uploadAvatar(data, userID: userID)
        invalidate()
    }

    public func chickenCost() async throws -> Int {
        _ = try await bootstrap()
        return try await reader.chickenCost()
    }

    public func react(commentID: Int, postID: Int, reaction: CommentReaction, userID: Int? = nil) async throws -> ReactionResponse {
        let authentication = try await bootstrap()
        guard let signedInUser = authentication.user else { throw SiteError.message("登录已过期，请在官网登录后重试。") }
        if let userID, signedInUser.id != userID { throw CancellationError() }
        let result = try await reader.react(commentID: commentID, reaction: reaction, userID: signedInUser.id)
        invalidateThread(id: postID)
        return result
    }
}

private struct TelegramBindingStatus: Decodable { let userID: Int; let bound: Bool }

private struct CreatedVoteResponse: Decodable {
    let vote: Vote
    struct Vote: Decodable { let id: Int }
}

private struct WebsitePreferenceResponse: Decodable {
    let data: Preferences
    struct Preferences: Decodable { let enable_festivous_style: Bool? }
}

private struct WebsiteStyleResponse: Decodable { let data: String? }
private struct TransferPreparation: Decodable { let receiver_name: String }
