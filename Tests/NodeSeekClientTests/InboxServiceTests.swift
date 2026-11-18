import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

@MainActor
struct InboxServiceTests {
    @Test func confirmedReadUpdatesConversationAndListEvenIfUnreadRefreshFails() async throws {
        let site = try TestInboxWebsite()
        let inbox = InboxService(website: site)
        inbox.reset(userID: 1, unreadCount: 4)
        try await inbox.loadConversation(peerID: 2, userID: 1)
        try await inbox.loadThreads(userID: 1)
        site.failUnreadRefresh = true

        try await inbox.markConversationRead(peerID: 2, userID: 1)

        #expect(site.markedIDs == [10])
        #expect(inbox.conversations[2]?.items.first?.viewed == true)
        #expect(inbox.threads?.items.first?.viewed == true)
        #expect(inbox.unreadCount == 4)
        site.failUnreadRefresh = false
        await inbox.refreshUnread()
        #expect(inbox.unreadCount == 3)
    }

    @Test func rejectedReadKeepsExistingUnreadState() async throws {
        let site = try TestInboxWebsite()
        let inbox = InboxService(website: site)
        inbox.reset(userID: 1, unreadCount: 4)
        try await inbox.loadConversation(peerID: 2, userID: 1)
        try await inbox.loadThreads(userID: 1)
        site.failMarkRead = true

        await #expect(throws: TestInboxWebsite.Failure.self) { try await inbox.markConversationRead(peerID: 2, userID: 1) }
        #expect(inbox.conversations[2]?.items.first?.viewed == false)
        #expect(inbox.threads?.items.first?.viewed == false)
        #expect(inbox.unreadCount == 4)
    }

    @Test func listRetriesWhenAReadReceiptMakesItsResponseOutdated() async throws {
        let site = try TestInboxWebsite()
        let inbox = InboxService(website: site)
        inbox.reset(userID: 1, unreadCount: 4)
        try await inbox.loadConversation(peerID: 2, userID: 1)
        try await inbox.loadThreads(userID: 1)

        let pending = await site.pauseNextThreadsRead {
            try await inbox.loadThreads(userID: 1, force: true)
        }
        try await inbox.markConversationRead(peerID: 2, userID: 1)
        site.resumeThreadsRead()

        try await pending.value
        #expect(site.threadReads == 3)
        #expect(inbox.threads?.items.first?.viewed == true)
    }

    @Test func markingOneConversationReadDoesNotInterruptAnother() async throws {
        let site = try TestInboxWebsite()
        let inbox = InboxService(website: site)
        inbox.reset(userID: 1, unreadCount: 4)
        try await inbox.loadConversation(peerID: 2, userID: 1)

        let pending = await site.pauseNextConversationRead {
            try await inbox.loadConversation(peerID: 3, userID: 1)
        }
        try await inbox.markConversationRead(peerID: 2, userID: 1)
        site.resumeConversationRead()

        try await pending.value
        #expect(site.conversationReads == [2, 3])
        #expect(inbox.conversations[2]?.items.first?.viewed == true)
        #expect(inbox.conversations[3]?.peer.id == 3)
    }

    @Test func oldResultsCannotEnterANewSessionForTheSameUser() async throws {
        let site = try TestInboxWebsite()
        let inbox = InboxService(website: site)
        inbox.reset(userID: 1, unreadCount: 4)
        let pending = await site.pauseNextThreadsRead { try await inbox.loadThreads(userID: 1) }

        inbox.reset(userID: nil, unreadCount: 0)
        inbox.reset(userID: 1, unreadCount: 7)
        site.resumeThreadsRead()

        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(inbox.threads == nil)
        #expect(inbox.unreadCount == 7)
    }

    @Test(arguments: [false, true])
    func markingAllNoticesRefreshesUnreadOnceAfterTheWrites(failsFirst: Bool) async throws {
        let site = try TestInboxWebsite()
        let inbox = InboxService(website: site)
        inbox.reset(userID: 1, unreadCount: 4)
        if failsFirst { site.failingNoticeKind = .replies }

        let (reads, continuation) = AsyncStream<[NoticeKind]>.makeStream()
        site.onUnreadRead = { continuation.yield(site.noticeWrites) }
        if failsFirst {
            await #expect(throws: TestInboxWebsite.Failure.self) { try await inbox.markAllNoticesRead(userID: 1) }
        } else {
            try await inbox.markAllNoticesRead(userID: 1)
        }

        var iterator = reads.makeAsyncIterator()
        let writesAtRefresh = await iterator.next()
        continuation.finish()
        site.onUnreadRead = nil
        #expect(writesAtRefresh == NoticeKind.allCases)
        #expect(site.unreadReads == 1)
        #expect(site.noticeWrites == NoticeKind.allCases)
    }

    @Test func confirmedSendSurvivesAFailedListRefresh() async throws {
        let site = try TestInboxWebsite()
        let inbox = InboxService(website: site)
        inbox.reset(userID: 1, unreadCount: 4)
        try await inbox.loadThreads(userID: 1)
        site.failThreadsRead = true

        try await inbox.send("你好", markdown: false, peerID: 2, userID: 1)

        #expect(site.sent == ["你好"])
        #expect(inbox.threads?.items.count == 1)
    }

    @Test func unreadIncreaseRefreshesLoadedListsWithoutFetchingUnvisitedOnes() async throws {
        let site = try TestInboxWebsite()
        site.currentUnreadCount = 1
        let inbox = InboxService(website: site)
        inbox.reset(userID: 1, unreadCount: 1)

        // Before any inbox tab has been visited, badge polling only updates the count.
        site.currentUnreadCount = 2
        await inbox.refreshUnread()
        #expect(inbox.unreadCount == 2)
        #expect(site.threadReads == 0)
        #expect(site.noticeReads.isEmpty)

        try await inbox.loadThreads(userID: 1)
        try await inbox.loadNotices(.replies, userID: 1)
        #expect(site.threadReads == 1)
        #expect(site.noticeReads == [.replies])

        // A new unread item refreshes already-loaded threads and replies with `force: true`, leaving `.mentions` untouched.
        site.currentUnreadCount = 4
        await inbox.refreshUnread()
        #expect(inbox.unreadCount == 4)
        #expect(site.threadReads == 2)
        #expect(site.lastThreadsForce == true)
        #expect(site.noticeReads == [.replies, .replies])
        #expect(site.lastNoticeForce == true)

        // Same or lower unread counts do not re-fetch lists.
        await inbox.refreshUnread()
        site.currentUnreadCount = 3
        await inbox.refreshUnread()
        #expect(inbox.unreadCount == 3)
        #expect(site.threadReads == 2)
        #expect(site.noticeReads == [.replies, .replies])
    }
}

@MainActor
private final class TestInboxWebsite: InboxWebsite {
    enum Failure: Error { case network }

    private let conversationValue: ConversationData
    private var threadsValue: AccountPage<MessageThread>
    private var didStartThreadsRead: CheckedContinuation<Void, Never>?
    private var finishThreadsRead: CheckedContinuation<Void, Never>?
    private var didStartConversationRead: CheckedContinuation<Void, Never>?
    private var finishConversationRead: CheckedContinuation<Void, Never>?
    private(set) var threadReads = 0
    private(set) var lastThreadsForce: Bool?
    private(set) var conversationReads: [Int] = []
    private(set) var unreadReads = 0
    private(set) var noticeReads: [NoticeKind] = []
    private(set) var lastNoticeForce: Bool?
    private(set) var noticeWrites: [NoticeKind] = []
    var currentUnreadCount = 3
    var onUnreadRead: (() -> Void)?
    var failingNoticeKind: NoticeKind?
    var failUnreadRefresh = false
    var failMarkRead = false
    var failThreadsRead = false
    var markedIDs: [Int]?
    var sent: [String] = []

    init() throws {
        conversationValue = try JSONDecoder().decode(ConversationData.self, from: Data(#"""
        {"peer":{"id":2,"name":"Reader"},"items":[
          {"id":10,"senderID":2,"receiverID":1,"content":"Hello","createdAt":"2026-11-01","isMarkdown":false,"viewed":false}
        ]}
        """#.utf8))
        threadsValue = try JSONDecoder().decode(AccountPage<MessageThread>.self, from: Data(#"""
        {"items":[{"id":2,"name":"Reader","preview":"Hello","createdAt":"2026-11-01","viewed":false}],"hasNext":false}
        """#.utf8))
    }

    func pauseNextThreadsRead(_ operation: @escaping @MainActor () async throws -> Void) async -> Task<Void, any Error> {
        let task = Task { try await operation() }
        await withCheckedContinuation { didStartThreadsRead = $0 }
        return task
    }

    func resumeThreadsRead() {
        finishThreadsRead?.resume()
        finishThreadsRead = nil
    }

    func pauseNextConversationRead(_ operation: @escaping @MainActor () async throws -> Void) async -> Task<Void, any Error> {
        let task = Task { try await operation() }
        await withCheckedContinuation { didStartConversationRead = $0 }
        return task
    }

    func resumeConversationRead() {
        finishConversationRead?.resume()
        finishConversationRead = nil
    }

    func unreadCount(userID: Int) async throws -> Int {
        unreadReads += 1
        onUnreadRead?()
        if failUnreadRefresh { throw Failure.network }
        return currentUnreadCount
    }

    func messageThreads(userID: Int, force: Bool) async throws -> AccountPage<MessageThread> {
        threadReads += 1
        lastThreadsForce = force
        if failThreadsRead { throw Failure.network }
        let value = threadsValue
        if let started = didStartThreadsRead {
            didStartThreadsRead = nil
            await withCheckedContinuation { finishThreadsRead = $0; started.resume() }
        }
        return value
    }

    func conversation(peerID: Int, userID: Int, force: Bool) async throws -> ConversationData {
        conversationReads.append(peerID)
        if let started = didStartConversationRead {
            didStartConversationRead = nil
            await withCheckedContinuation { finishConversationRead = $0; started.resume() }
        }
        if peerID == 2 { return conversationValue }
        return try JSONDecoder().decode(ConversationData.self, from: Data(#"""
        {"peer":{"id":3,"name":"Second reader"},"items":[]}
        """#.utf8))
    }
    func notices(_ kind: NoticeKind, userID: Int, force: Bool) async throws -> AccountPage<ForumNotice> {
        noticeReads.append(kind)
        lastNoticeForce = force
        return .init(items: [], hasNext: false)
    }
    func markNoticesRead(_ kind: NoticeKind, ids: [Int]?, userID: Int) async throws {
        noticeWrites.append(kind)
        if kind == failingNoticeKind { throw Failure.network }
    }

    func markMessagesRead(ids: [Int]?, peerID: Int?, userID: Int) async throws {
        if failMarkRead { throw Failure.network }
        markedIDs = ids
        var items = threadsValue.items
        for index in items.indices where peerID == nil || items[index].id == peerID {
            items[index].viewed = true
        }
        threadsValue = AccountPage(items: items, hasNext: threadsValue.hasNext, cursor: threadsValue.cursor)
    }

    func sendMessage(_ content: String, markdown: Bool, peerID: Int, userID: Int) async throws { sent.append(content) }
}
