import NodeSeekCore

@MainActor
protocol InboxWebsite {
    func unreadCount(userID: Int) async throws -> Int
    func messageThreads(userID: Int, force: Bool) async throws -> AccountPage<MessageThread>
    func conversation(peerID: Int, userID: Int, force: Bool) async throws -> ConversationData
    func notices(_ kind: NoticeKind, userID: Int, force: Bool) async throws -> AccountPage<ForumNotice>
    func markMessagesRead(ids: [Int]?, peerID: Int?, userID: Int) async throws
    func markNoticesRead(_ kind: NoticeKind, ids: [Int]?, userID: Int) async throws
    func sendMessage(_ content: String, markdown: Bool, peerID: Int, userID: Int) async throws
}

extension SiteDataStore: InboxWebsite {
    static let unreadCountPath = "/api/notification/unread-count"

    func unreadCount(userID: Int) async throws -> Int {
        let response: UnreadResponse = try await json(path: Self.unreadCountPath, requiresLogin: true, force: true, lifetime: 5, expectedUserID: userID)
        return response.unreadCount.all
    }

    func messageThreads(userID: Int, force: Bool) async throws -> AccountPage<MessageThread> {
        try await account(.messages, userID: userID, force: force)
    }

    func conversation(peerID: Int, userID: Int, force: Bool) async throws -> ConversationData {
        try await account(.conversation(peerID), userID: userID, force: force)
    }

    func notices(_ kind: NoticeKind, userID: Int, force: Bool) async throws -> AccountPage<ForumNotice> {
        try await account(.notices(kind), userID: userID, force: force)
    }

    func markMessagesRead(ids: [Int]?, peerID: Int?, userID: Int) async throws {
        _ = try await action(path: "/api/notification/message/markViewed" + (ids == nil ? "?all=true" : ""),
                             body: ids.map { ["messages": $0] } ?? [:], userID: userID, headers: [:], messagePeerID: peerID)
    }

    func markNoticesRead(_ kind: NoticeKind, ids: [Int]?, userID: Int) async throws {
        let key = kind == .replies ? "replys" : "atMe"
        _ = try await action(path: "/api/notification/\(kind.rawValue)/markViewed" + (ids == nil ? "?all=true" : ""),
                             body: ids.map { [key: $0] } ?? [:], userID: userID, headers: [:])
    }

    func sendMessage(_ content: String, markdown: Bool, peerID: Int, userID: Int) async throws {
        _ = try await action(path: "/api/notification/message/send",
                             body: ["receiverUid": peerID, "content": content, "markdown": markdown], userID: userID, headers: [:], messagePeerID: peerID)
    }
}

private struct UnreadResponse: Decodable {
    let unreadCount: Counts
    struct Counts: Decodable { let all: Int }
}
