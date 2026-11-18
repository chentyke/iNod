import Foundation
import Testing
@testable import NodeSeekCore

@Test func routesMatchWebsite() {
    #expect(NodeSeekRoute.feed(category: "", sort: .replyTime, page: 1).url.absoluteString == "https://www.nodeseek.com/?sortBy=replyTime")
    #expect(NodeSeekRoute.feed(category: "tech", sort: .postTime, page: 3).url.absoluteString == "https://www.nodeseek.com/categories/tech/page-3?sortBy=postTime")
    #expect(NodeSeekRoute.thread(id: 123, page: 2).url.path == "/post-123-2")
}

@Test func searchSafelyEncodesInput() throws {
    let url = NodeSeekRoute.search(query: "C++ & iOS? #中文", category: "tech", sort: .postTime, page: 2).url
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.first { $0.name == "q" }?.value == "C++ & iOS? #中文")
    #expect(url.absoluteString.contains("C%2B%2B"))
    #expect(items.first { $0.name == "page" }?.value == "2")
    #expect(url.host() == "www.nodeseek.com")
    #expect(url.fragment == nil)
}

@Test func invalidPageUsesFirstPage() {
    #expect(NodeSeekRoute.thread(id: 1, page: -4).url.path == "/post-1-1")
    #expect(NodeSeekRoute.feed(category: "", sort: .replyTime, page: 0).url.path == "/")
}

@Test func decodesWebsiteThreadSample() throws {
    let url = try #require(Bundle.module.url(forResource: "thread", withExtension: "json", subdirectory: "Fixtures"))
    let detail = try JSONDecoder().decode(PostDetail.self, from: Data(contentsOf: url))
    #expect(detail.postId == 123)
    #expect(detail.postPageCount == 3)
    #expect(detail.comments.first?.poster.uid == 101)
    #expect(detail.op.avatarURL?.path == "/avatar/101.png")
    #expect(detail.comments.first?.floorIndex == 0)
    #expect(detail.comments.first?.time.date != nil)
    #expect(detail.comments.first?.markdown.isEmpty == false)
}

@Test func postSummariesKeepReadingLevelAndReadOlderSavedPosts() throws {
    let saved = #"{"id":1,"title":"测试","author":"","avatar":"","category":"","categoryKey":"","views":0,"replies":0,"activityDate":"","pinned":false}"#
    let decoder = JSONDecoder()
    var post = try decoder.decode(PostSummary.self, from: Data(saved.utf8))
    #expect(post.rank == nil)
    post.rank = 3
    let encoded = try JSONEncoder().encode(post)
    #expect(try decoder.decode(PostSummary.self, from: encoded).rank == 3)
}

@Test(arguments: [
    ("2026-10-15T13:00:00.125Z", 1_792_069_200.125 as Double?),
    ("2026-10-15T21:00:00.250+08:00", 1_792_069_200.250),
    ("2026-10-15T13:00:00Z", nil),
    ("invalid", nil),
    ("", nil)
])
func postActivityDateKeepsWebsiteTimestampRules(_ rawDate: String, _ expectedTimestamp: Double?) {
    let post = PostSummary(id: 1, title: "测试", author: "", avatar: "", category: "", categoryKey: "",
                           views: 0, replies: 0, activityDate: rawDate, pinned: false)

    #expect(post.parsedActivityDate?.timeIntervalSince1970 == expectedTimestamp)
}

@Test func markdownKeepsCodeAndImagesSeparate() {
    let blocks = MarkdownBlock.parse("# 标题\n\n正文 **加粗**\n\n```swift\nlet x = 1\n```\n\n![截图](https://example.com/a.png)")
    #expect(blocks == [.heading("标题"), .text("正文 **加粗**"), .code("let x = 1"), .image(alt: "截图", url: URL(string: "https://example.com/a.png")!)])
}

@Test func markdownRendersImagesWithAngleBracketDestinations() {
    let markdown = "前文\n![image](<https://example.com/receipt(1).png>)\n后文"
    #expect(MarkdownBlock.parse(markdown) == [
        .text("前文"),
        .image(alt: "image", url: URL(string: "https://example.com/receipt(1).png")!),
        .text("后文")
    ])
}

@Test func unfinishedCodeFencePreservesContent() {
    #expect(MarkdownBlock.parse("```\n# code\ntext") == [.code("# code\ntext")])
}

@Test func categoriesHaveUniqueIdentifiers() {
    #expect(Set(ForumCategory.all.map(\.id)).count == ForumCategory.all.count)
    #expect(ForumCategory.all.contains { $0.id == "photo-share" })
}

@Test func stickersMatchOfficialAssetNames() throws {
    #expect(try #require(ForumSticker.named("xhj003")).url.path == "/static/image/sticker/xhj/003.png")
    #expect(try #require(ForumSticker.named("xhj004")).url.path == "/static/image/sticker/xhj/004.gif")
    #expect(try #require(ForumSticker.named("yct001")).url.path == "/static/image/sticker/yct/001.gif")
    #expect(try #require(ForumSticker.named("ac01")).url.path == "/static/image/sticker/ac/01.png")
    #expect(try #require(ForumSticker.named("emoji00")).url.path == "/static/image/sticker/emoji/00.mov")
    #expect(ForumSticker.named("xhj999") == nil)
}

@Test func stickersStayInlineWithSurroundingText() throws {
    let sticker = try #require(ForumSticker.named("xhj003"))
    #expect(InlineContent.parse("码一个 :xhj003: 好的") == [.text("码一个 "), .sticker(sticker), .text(" 好的")])
    #expect(InlineContent.parse(":xhj003::xhj003:") == [.sticker(sticker), .sticker(sticker)])
}

@Test func stickerCodesInCodeAndURLsArePreserved() {
    let text = "代码 `:xhj003:` 地址 https://example.com/:xhj003: 未知 :xhj999:"
    #expect(InlineContent.parse(text) == [.text(text)])
}

@Test func sessionDistinguishesGuestFromSignedInUser() throws {
    let decoder = JSONDecoder()
    let signedIn = try decoder.decode(AuthenticationSnapshot.self, from: Data(#"{"ready":true,"user":{"id":123,"name":"test-user","coins":399,"topicCount":2}}"#.utf8))
    #expect(signedIn.ready)
    #expect(signedIn.user?.id == 123)
    #expect(signedIn.user?.level == 1)
    #expect(signedIn.user?.unreadCount == nil)
    #expect(signedIn.user?.collectionCount == nil)
    let guest = try decoder.decode(AuthenticationSnapshot.self, from: Data(#"{"ready":true,"user":null}"#.utf8))
    #expect(guest.user == nil)
    #expect(throws: (any Error).self) {
        try decoder.decode(AuthenticationSnapshot.self, from: Data(#"{"ready":true,"user":{"name":"test-user"}}"#.utf8))
    }
}

@Test func accountLevelsMatchWebsiteAndLinksKeepSections() throws {
    let decoder = JSONDecoder()
    for (coins, level) in [(-1, 0), (0, 0), (99, 0), (100, 1), (399, 1), (400, 2), (900, 3), (1600, 4), (2500, 5), (3599, 5), (3600, 6), (10000, 6)] {
        let data = Data("{\"id\":123,\"name\":\"test-user\",\"coins\":\(coins)}".utf8)
        let user = try decoder.decode(SignedInUser.self, from: data)
        let profile = try decoder.decode(AccountProfile.self, from: data)
        #expect(user.level == level)
        #expect(profile.level == level)
        #expect(user.spaceURL(section: "collections").absoluteString == "https://www.nodeseek.com/space/123#collections")
    }
}

@Test func chickenCostUsesRemainingFreeQuota() throws {
    for (used, cost) in [(0, 0), (2, 0), (3, 1), (4, 1)] {
        let quota = try JSONDecoder().decode(FreeLikeQuota.self, from: Data("{\"maxFreeLike\":3,\"freeLikeUsed\":\(used)}".utf8))
        #expect(quota.cost == cost)
    }
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(FreeLikeQuota.self, from: Data(#"{"message":"请登录"}"#.utf8))
    }
}

@Test func reactionUsesServerCountAndPreservesOtherCounts() throws {
    let url = try #require(Bundle.module.url(forResource: "thread", withExtension: "json", subdirectory: "Fixtures"))
    let detail = try JSONDecoder().decode(PostDetail.self, from: Data(contentsOf: url))
    var comment = try #require(detail.comments.first)
    let originalUpvotes = comment.upvoteCount
    let response = try JSONDecoder().decode(ReactionResponse.self, from: Data(#"{"success":true,"current":12,"coin":99}"#.utf8))
    comment.apply(.like, count: try #require(response.current))
    #expect(comment.likeCount == 12)
    #expect(comment.hasReacted(.like))
    #expect(comment.upvoteCount == originalUpvotes)
    #expect(response.coin == 99)
    let rejected = try JSONDecoder().decode(ReactionResponse.self, from: Data(#"{"success":false,"message":"已投喂"}"#.utf8))
    #expect(!rejected.success)
    #expect(rejected.current == nil)
}

@Test func accountReplyLinksUseWebsiteFloorPagination() throws {
    for (floor, page) in [(0,1),(10,1),(11,2),(20,2),(21,3)] {
        let item = try JSONDecoder().decode(AccountPost.self, from: Data("{\"id\":\"123-\(floor)\",\"postID\":123,\"title\":\"test\",\"floor\":\(floor),\"excerpt\":null,\"rank\":0}".utf8))
        #expect(item.page == page)
        #expect(item.summary.id == 123)
    }
}

@Test func accountPagesPreserveEmptyListsAndCursor() throws {
    let page = try JSONDecoder().decode(AccountPage<LedgerEntry>.self, from: Data(#"{"items":[],"hasNext":false,"cursor":null}"#.utf8))
    #expect(page.items.isEmpty)
    #expect(!page.hasNext)
    #expect(page.cursor == nil)
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(AccountPage<LedgerEntry>.self, from: Data(#"{"success":false,"message":"请登录"}"#.utf8))
    }
}

@Test func appendingAPageKeepsEarlierRowsAndUsesTheNewCursor() throws {
    let decoder = JSONDecoder()
    let first = try decoder.decode(StardustRecords.self, from: Data("""
        {"records":[{"id":3,"diff":1,"result":5,"type":"upvote","created_at":""}],"exist_more":true,"cursor":3}
        """.utf8))
    let second = try decoder.decode(StardustRecords.self, from: Data("""
        {"records":[
            {"id":3,"diff":1,"result":5,"type":"upvote","created_at":""},
            {"id":2,"diff":1,"result":4,"type":"upvote","created_at":""},
            {"id":2,"diff":1,"result":4,"type":"upvote","created_at":""}
        ],"exist_more":false,"cursor":2}
        """.utf8))

    let combined = appendPage(\StardustRecords.records)(first, second)

    #expect(first.records.map(\.id) == [3])
    #expect(combined.records.map(\.id) == [3, 2])
    #expect(combined.cursor == 2)
    #expect(combined.exist_more == false)
}

@Test func ledgerPreservesNegativeChangesAndExactBalance() throws {
    let entry = try JSONDecoder().decode(LedgerEntry.self, from: Data(#"{"id":"row-1","change":-2,"balance":561,"reason":"反对","createdAt":"2026-10-15T13:00:00.000Z","peerID":null}"#.utf8))
    #expect(entry.change == -2)
    #expect(entry.balance == 561)
    #expect(ForumDate.parse(entry.createdAt) != nil)
}

@Test func attendanceDistinguishesNotSignedInFromZeroReward() throws {
    let board = try JSONDecoder().decode(AttendanceBoard.self, from: Data(#"{"gain":null,"order":null,"total":50,"items":[],"hasNext":false}"#.utf8))
    #expect(board.gain == nil)
    #expect(board.createdAt == nil)
    let signed = try JSONDecoder().decode(AttendanceBoard.self, from: Data(#"{"gain":0,"order":3,"createdAt":"2026-11-17T00:02:18.000Z","total":50,"items":[{"id":9,"name":"读者","gain":0,"rank":3}],"hasNext":false}"#.utf8))
    #expect(signed.gain == 0)
    #expect(signed.order == 3)
    #expect(ForumDate.parse(try #require(signed.createdAt)) != nil)
    #expect(signed.items.first?.rank == 3)
}

@Test func datesAcceptWebsiteFormatsAndKeepMissingValuesUnknown() {
    #expect(ForumDate.parse("2026-10-15T13:00:00.000Z") == ForumDate.parse("2026-10-15T13:00:00Z"))
    #expect(ForumDate.parse("1792069200000") == ForumDate.parse("1792069200"))
    #expect(ForumDate.parse("") == nil)
    #expect(ForumDate.parse("invalid") == nil)
    #expect(ForumDate.parse("inf") == nil)
}

@Test func forumImagesSendWebsiteOriginWithoutCredentials() throws {
    let url = try #require(URL(string: "https://i.111666.best/image/test.png"))
    let request = ForumImageRequest.make(url: url)
    #expect(request.url == url)
    #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/")
    #expect(request.value(forHTTPHeaderField: "Accept")?.contains("image/") == true)
    #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}
