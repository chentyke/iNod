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

    @Test func oldListCannotUndoAConfirmedRead() async throws {
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

        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(inbox.threads?.items.first?.viewed == true)
        #expect(inbox.unreadCount == 3)
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
}

@MainActor
private final class TestInboxWebsite: InboxWebsite {
    enum Failure: Error { case network }

    private let conversationValue: ConversationData
    private let threadsValue: AccountPage<MessageThread>
    private var didStartThreadsRead: CheckedContinuation<Void, Never>?
    private var finishThreadsRead: CheckedContinuation<Void, Never>?
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

    func unreadCount(userID: Int) async throws -> Int {
        if failUnreadRefresh { throw Failure.network }
        return 3
    }

    func messageThreads(userID: Int, force: Bool) async throws -> AccountPage<MessageThread> {
        if failThreadsRead { throw Failure.network }
        if let started = didStartThreadsRead {
            didStartThreadsRead = nil
            await withCheckedContinuation { finishThreadsRead = $0; started.resume() }
        }
        return threadsValue
    }

    func conversation(peerID: Int, userID: Int, force: Bool) async throws -> ConversationData { conversationValue }
    func notices(_ kind: NoticeKind, userID: Int, force: Bool) async throws -> AccountPage<ForumNotice> { .init(items: [], hasNext: false) }
    func markNoticesRead(_ kind: NoticeKind, ids: [Int]?, userID: Int) async throws { }

    func markMessagesRead(ids: [Int]?, userID: Int) async throws {
        if failMarkRead { throw Failure.network }
        markedIDs = ids
    }

    func sendMessage(_ content: String, markdown: Bool, peerID: Int, userID: Int) async throws { sent.append(content) }
}
