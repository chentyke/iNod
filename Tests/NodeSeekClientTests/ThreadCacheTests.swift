#if DEBUG
import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

@MainActor
struct ThreadCacheTests {
    enum Change: CaseIterable {
        case reply, bookmark, reaction, editReply, pinReply, newPost

        var changesFeed: Bool { self != .bookmark && self != .reaction }
    }

    @Test(arguments: Change.allCases)
    func reopeningOfflineAfterAChangeKeepsUnaffectedPosts(_ change: Change) async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = 4
        let auth = try JSONDecoder().decode(AuthenticationSnapshot.self, from: Data(#"{"ready":true,"user":{"id":4,"name":"读者"}}"#.utf8))
        let disk = PersistentResponseStore(directory: directory)
        let website = SiteDataStore(disk: disk, defaults: defaults) { auth }
        _ = try await website.bootstrap()

        let first = website.threadKey(id: 10, page: 1, includeBlocked: false, viewerID: owner)
        let second = website.threadKey(id: 10, page: 2, includeBlocked: false, viewerID: owner)
        let other = website.threadKey(id: 100, page: 1, includeBlocked: false, viewerID: owner)
        let feed = website.feedKey(.home, includeBlocked: false, viewerID: owner)
        for (key, id, page) in [(first, 10, 1), (second, 10, 2), (other, 100, 1)] {
            let json = """
            {"postId":\(id),"postPage":\(page),"postPageCount":2,"title":"原帖","categoryWord":"日常","views":"1",
             "collectionCount":0,"op":{"uid":4,"name":"读者"},"comments":[]}
            """
            disk.insert(Data(json.utf8), kind: key.kind, path: key.path, owner: owner)
        }
        disk.insert(Data(#"{"posts":[],"hasNextPage":false}"#.utf8), kind: feed.kind, path: feed.path, owner: owner)
        await disk.finishPendingWrites()
        #expect(website.cached(PostDetail.self, key: second)?.postPage == 2)

        let draft = EditorDraft(title: "标题", content: "帖子内容")
        let reply = WebsiteAction.publish(draft: draft, mode: .reply(postID: 10))
        let ok = Data(#"{"success":true}"#.utf8)
        switch change {
        case .reply:
            website.responsesForUITests = [:]
            await #expect(throws: SiteError.self) {
                let _: ReactionResponse = try await website.perform(reply, userID: owner)
            }
            #expect(website.cached(PostDetail.self, key: first)?.postId == 10)
            website.responsesForUITests = ["POST /api/content/new-comment": ok]
            let _: ReactionResponse = try await website.perform(reply, userID: owner)
        case .bookmark:
            website.responsesForUITests = ["POST /api/statistics/collection": ok]
            try await website.setCollected(true, postID: 10, userID: owner)
        case .reaction:
            await website.invalidateThread(id: 10, userID: owner)
        case .editReply, .pinReply:
            let action = change == .editReply ? WebsiteAction.publish(draft: draft, mode: .editComment(commentID: 8))
                : .pinComment(id: 8, pinned: false)
            website.responsesForUITests = ["POST " + action.request.path: ok]
            let _: ReactionResponse = try await website.perform(action, userID: owner, affectedPostID: 10)
        case .newPost:
            website.responsesForUITests = ["POST /api/content/new-discussion": ok]
            let _: ReactionResponse = try await website.perform(.publish(draft: draft, mode: .newPost), userID: owner)
        }

        let reopened = SiteDataStore(disk: PersistentResponseStore(directory: directory), defaults: defaults) {
            throw URLError(.notConnectedToInternet)
        }
        await #expect(throws: URLError.self) { try await reopened.bootstrap() }
        func offlineKey(_ key: SiteRequestKey) -> SiteRequestKey {
            SiteRequestKey(userID: nil, kind: key.kind, path: key.path)
        }
        for key in [first, second] {
            let cached = reopened.cached(PostDetail.self, key: offlineKey(key))
            #expect(cached?.postId == (change == .newPost ? 10 : nil))
        }
        #expect(reopened.cached(FeedPage.self, key: offlineKey(feed))?.posts.isEmpty == (change.changesFeed ? nil : true))
        #expect(reopened.cached(PostDetail.self, key: offlineKey(other))?.postId == 100)
    }
}
#endif
