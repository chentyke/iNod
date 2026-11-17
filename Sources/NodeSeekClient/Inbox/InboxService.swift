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
    private var threadsChanged = 0
    private var allConversationsChanged = 0
    private var conversationsChanged: [Int: Int] = [:]
    private var noticesChanged: [NoticeKind: Int] = [:]
    private var markingConversations: Set<Int> = []

    init(website: any InboxWebsite) { self.website = website }

    func reset(userID: Int?, unreadCount: Int) {
        changes += 1
        session = changes
        self.userID = userID
        self.unreadCount = unreadCount
        threads = nil
        conversations.removeAll()
        notices.removeAll()
        conversationsChanged.removeAll()
        noticesChanged.removeAll()
        markingConversations.removeAll()
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
        try await read(since: { threadsChanged }) {
            try await website.messageThreads(userID: userID, force: force)
        } apply: {
            threads = $0
        }
    }

    public func loadConversation(peerID: Int, userID: Int, force: Bool = false) async throws {
        try checkOwner(userID)
        try await read(since: { max(allConversationsChanged, conversationsChanged[peerID] ?? 0) }) {
            try await website.conversation(peerID: peerID, userID: userID, force: force)
        } apply: {
            conversations[peerID] = $0
        }
    }

    public func loadNotices(_ kind: NoticeKind, userID: Int, force: Bool = false) async throws {
        try checkOwner(userID)
        try await read(since: { noticesChanged[kind] ?? 0 }) {
            try await website.notices(kind, userID: userID, force: force)
        } apply: {
            notices[kind] = $0
        }
    }

    public func markConversationRead(peerID: Int, userID: Int) async throws {
        try checkOwner(userID)
        let ids = Set(conversations[peerID]?.items.filter { !$0.viewed && $0.receiverID == userID }.map(\.id) ?? [])
        guard !ids.isEmpty, markingConversations.insert(peerID).inserted else { return }
        let version = session
        defer { if session == version { markingConversations.remove(peerID) } }
        try await website.markMessagesRead(ids: ids.sorted(), peerID: peerID, userID: userID)
        try confirmMessageChange(version, peerID: peerID)
        updateConversation(peerID: peerID, userID: userID, ids: ids)
        refreshUnreadInBackground(session: version)
    }

    public func markAllMessagesRead(userID: Int) async throws {
        try checkOwner(userID)
        let version = session
        let previousThreads = Set(threads?.items ?? [])
        let previousIDs = conversations.mapValues { Set($0.items.map(\.id)) }
        try await website.markMessagesRead(ids: nil, peerID: nil, userID: userID)
        try confirmMessageChange(version, peerID: nil)
        updateThreads { previousThreads.contains($0) }
        for (peerID, ids) in previousIDs { updateConversation(peerID: peerID, userID: userID, ids: ids) }
        await refreshUnread()
        try checkSession(version)
    }

    public func markNoticesRead(_ kind: NoticeKind, ids: [Int]?, userID: Int) async throws {
        let version = session
        try await markNotices(kind, ids: ids, userID: userID)
        refreshUnreadInBackground(session: version)
    }

    public func markAllNoticesRead(userID: Int) async throws {
        try checkOwner(userID)
        let version = session
        var didMark = false
        var failure: (any Error)?
        defer { if didMark { refreshUnreadInBackground(session: version) } }
        for kind in NoticeKind.allCases {
            try Task.checkCancellation()
            try checkSession(version)
            do {
                try await markNotices(kind, ids: nil, userID: userID)
                didMark = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
    }

    private func markNotices(_ kind: NoticeKind, ids: [Int]?, userID: Int) async throws {
        try checkOwner(userID)
        let version = session
        let affected = Set(ids ?? notices[kind]?.items.map(\.id) ?? [])
        try await website.markNoticesRead(kind, ids: ids, userID: userID)
        try confirmChange(version)
        noticesChanged[kind] = changes
        if let page = notices[kind] {
            notices[kind] = AccountPage(items: page.items.map { notice in
                var notice = notice
                if affected.contains(notice.id) { notice.viewed = true }
                return notice
            }, hasNext: page.hasNext, cursor: page.cursor)
        }
    }

    private func refreshUnreadInBackground(session version: Int) {
        Task { [weak self] in
            guard let self, self.session == version else { return }
            await self.refreshUnread()
        }
    }

    public func send(_ content: String, markdown: Bool, peerID: Int, userID: Int) async throws {
        try checkOwner(userID)
        let version = session
        try await website.sendMessage(content, markdown: markdown, peerID: peerID, userID: userID)
        try confirmMessageChange(version, peerID: peerID)
        if threads != nil {
            Task { [weak self] in
                guard let self, self.session == version else { return }
                try? await self.loadThreads(userID: userID, force: true)
            }
        }
    }

    private func checkOwner(_ userID: Int) throws {
        guard self.userID == userID else { throw CancellationError() }
    }

    private func checkSession(_ version: Int) throws {
        guard session == version else { throw CancellationError() }
    }

    private func read<Value>(
        since lastChange: () -> Int,
        fetch: () async throws -> Value,
        apply: (Value) -> Void
    ) async throws {
        let started = changes
        do {
            let value = try await fetch()
            try checkRead(started, since: lastChange())
            apply(value)
        } catch is CancellationError {
            // A write can invalidate a request while the page is still waiting for it.
            try checkRead(started, since: session)
            let retry = changes
            let value = try await fetch()
            try checkRead(retry, since: lastChange())
            apply(value)
        }
    }

    private func checkRead(_ version: Int, since lastChange: Int) throws {
        try Task.checkCancellation()
        guard version >= max(session, lastChange) else { throw CancellationError() }
    }

    private func confirmChange(_ version: Int) throws {
        try checkSession(version)
        changes += 1
    }

    private func confirmMessageChange(_ version: Int, peerID: Int?) throws {
        try confirmChange(version)
        threadsChanged = changes
        if let peerID {
            conversationsChanged[peerID] = changes
        } else {
            allConversationsChanged = changes
            conversationsChanged.removeAll()
        }
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
