import NodeSeekCore

@MainActor
protocol InboxWebsite {
    func unreadCounts(userID: Int) async throws -> InboxUnreadCounts
    func messageThreads(userID: Int, force: Bool) async throws -> AccountPage<MessageThread>
    func conversation(peerID: Int, userID: Int, force: Bool) async throws -> ConversationData
    func notices(_ kind: NoticeKind, userID: Int, force: Bool) async throws -> AccountPage<ForumNotice>
    func markMessagesRead(ids: [Int]?, peerID: Int?, userID: Int) async throws
    func markNoticesRead(_ kind: NoticeKind, ids: [Int]?, userID: Int) async throws
    func sendMessage(_ content: String, markdown: Bool, peerID: Int, userID: Int) async throws
}

extension SiteDataStore: InboxWebsite {
    static let unreadCountPath = "/api/notification/unread-count"

    func unreadCounts(userID: Int) async throws -> InboxUnreadCounts {
        let response: UnreadResponse = try await json(path: Self.unreadCountPath, requiresLogin: true, force: true, lifetime: 5, expectedUserID: userID)
        return response.unreadCount
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

struct InboxUnreadCounts: Decodable {
    let all: Int
    private let message: Int?

    var messages: Int { min(max(0, message ?? 0), max(0, all)) }

    init(all: Int, message: Int? = nil) {
        self.all = all
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case all, message
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(all: try container.decode(Int.self, forKey: .all),
                  message: try? container.decode(Int.self, forKey: .message))
    }
}

private struct UnreadResponse: Decodable {
    let unreadCount: InboxUnreadCounts
}
