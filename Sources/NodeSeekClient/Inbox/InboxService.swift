import NodeSeekCore
import Observation

@MainActor
@Observable
public final class InboxService {
    public private(set) var unreadCount = 0
    public private(set) var threads: AccountPage<MessageThread>?
    public private(set) var conversations: [Int: ConversationData] = [:]
    public private(set) var notices: [NoticeKind: AccountPage<ForumNotice>] = [:]
    private let website: any InboxWebsite
    private var userID: Int?
    private var session = 0
    private var changes = 0

    init(website: any InboxWebsite) { self.website = website }

    func reset(userID: Int?, unreadCount: Int) {
        session += 1
        changes += 1
        self.userID = userID
        self.unreadCount = unreadCount
        threads = nil
        conversations.removeAll()
        notices.removeAll()
    }

    public func refreshUnread() async {
        guard let userID else { return }
        let version = changes
        do {
            let count = try await website.unreadCount(userID: userID)
            if version == changes, !Task.isCancelled { unreadCount = count }
        } catch { }
    }

    public func loadThreads(userID: Int, force: Bool = false) async throws {
        try checkOwner(userID)
        let version = changes
        let value = try await website.messageThreads(userID: userID, force: force)
        try checkRead(version)
        threads = value
    }

    public func loadConversation(peerID: Int, userID: Int, force: Bool = false) async throws {
        try checkOwner(userID)
        let version = changes
        let value = try await website.conversation(peerID: peerID, userID: userID, force: force)
        try checkRead(version)
        conversations[peerID] = value
    }

    public func loadNotices(_ kind: NoticeKind, userID: Int, force: Bool = false) async throws {
        try checkOwner(userID)
        let version = changes
        let value = try await website.notices(kind, userID: userID, force: force)
        try checkRead(version)
        notices[kind] = value
    }

    public func markConversationRead(peerID: Int, userID: Int) async throws {
        try checkOwner(userID)
        let ids = Set(conversations[peerID]?.items.filter { !$0.viewed && $0.receiverID == userID }.map(\.id) ?? [])
        guard !ids.isEmpty else { return }
        let version = session
        try await website.markMessagesRead(ids: ids.sorted(), userID: userID)
        try confirmChange(version)
        updateConversation(peerID: peerID, userID: userID, ids: ids)
        await refreshUnread()
        try checkSession(version)
    }

    public func markAllMessagesRead(userID: Int) async throws {
        try checkOwner(userID)
        let version = session
        let previousThreads = Set(threads?.items ?? [])
        let previousIDs = conversations.mapValues { Set($0.items.map(\.id)) }
        try await website.markMessagesRead(ids: nil, userID: userID)
        try confirmChange(version)
        updateThreads { previousThreads.contains($0) }
        for (peerID, ids) in previousIDs { updateConversation(peerID: peerID, userID: userID, ids: ids) }
        await refreshUnread()
        try checkSession(version)
    }

    public func markNoticesRead(_ kind: NoticeKind, ids: [Int]?, userID: Int) async throws {
        try checkOwner(userID)
        let version = session
        let affected = Set(ids ?? notices[kind]?.items.map(\.id) ?? [])
        try await website.markNoticesRead(kind, ids: ids, userID: userID)
        try confirmChange(version)
        if let page = notices[kind] {
            notices[kind] = AccountPage(items: page.items.map { notice in
                var notice = notice
                if affected.contains(notice.id) { notice.viewed = true }
                return notice
            }, hasNext: page.hasNext, cursor: page.cursor)
        }
        await refreshUnread()
        try checkSession(version)
    }

    public func send(_ content: String, markdown: Bool, peerID: Int, userID: Int) async throws {
        try checkOwner(userID)
        let version = session
        try await website.sendMessage(content, markdown: markdown, peerID: peerID, userID: userID)
        try confirmChange(version)
        // The send is confirmed even if the subsequent reads fail.
        if threads != nil { try? await loadThreads(userID: userID, force: true) }
        try checkSession(version)
    }

    private func checkOwner(_ userID: Int) throws {
        guard self.userID == userID else { throw CancellationError() }
    }

    private func checkSession(_ version: Int) throws {
        guard session == version else { throw CancellationError() }
    }

    private func checkRead(_ version: Int) throws {
        try Task.checkCancellation()
        guard changes == version else { throw CancellationError() }
    }

    private func confirmChange(_ version: Int) throws {
        try checkSession(version)
        changes += 1
    }

    private func updateConversation(peerID: Int, userID: Int, ids: Set<Int>) {
        guard var value = conversations[peerID] else { return }
        for index in value.items.indices where value.items[index].receiverID == userID && ids.contains(value.items[index].id) {
            value.items[index].viewed = true
        }
        conversations[peerID] = value
        if let latest = value.items.last, latest.receiverID == userID, latest.viewed {
            updateThreads { thread in
                guard thread.id == peerID else { return false }
                if let id = thread.latestMessageID { return id == latest.id }
                return thread.createdAt == latest.createdAt && thread.preview == latest.content
            }
        }
    }

    private func updateThreads(where matches: (MessageThread) -> Bool) {
        guard let page = threads else { return }
        threads = AccountPage(items: page.items.map { item in
            var item = item
            if matches(item) { item.viewed = true }
            return item
        }, hasNext: page.hasNext, cursor: page.cursor)
    }
}
