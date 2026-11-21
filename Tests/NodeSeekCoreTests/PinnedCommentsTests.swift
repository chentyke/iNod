import Foundation
import Testing
@testable import NodeSeekCore

@Test func pinnedRepliesAppearBeforeOrdinaryRepliesAndKeepTheirFloors() throws {
    let detail = try threadForDisplay([
        (1, 0, false), (2, 1, false), (76, 76, true), (3, 2, false), (50, 50, true)
    ])
    #expect(detail.replies.map(\.floorIndex) == [76, 50, 1, 2])
}

@Test func repeatedRepliesPreferThePinnedCopyAndAppearOnlyOnce() throws {
    let detail = try threadForDisplay([
        (1, 0, false), (76, 76, false), (2, 1, false), (76, 76, true),
        (76, 76, true), (2, 1, false), (3, 2, false)
    ])
    #expect(detail.replies.map(\.id) == [76, 2, 3])
    #expect(detail.replies.first?.pined == true)
}

@Test func ordinaryRepliesKeepTheWebsiteOrder() throws {
    let detail = try threadForDisplay([(1, 0, false), (5, 4, false), (2, 1, false), (3, 2, false)])
    #expect(detail.replies.map(\.floorIndex) == [4, 1, 2])
}

@Test func hotRepliesFollowPinnedRepliesAndKeepTheirFloors() throws {
    let detail = try threadForDisplay([
        (1, 0, false), (2, 1, false), (44, 44, false), (3, 2, false), (76, 76, true)
    ], hotCommentIndices: [2, 4])
    #expect(detail.replies.map(\.floorIndex) == [76, 44, 1, 2])
    #expect(detail.replies[1].hot == true)
    #expect(detail.replies[1].pined == false)
}

@Test func repeatedRepliesPreferTheHotCopyAndAppearOnlyOnce() throws {
    let detail = try threadForDisplay([
        (1, 0, false), (44, 44, false), (2, 1, false), (44, 44, false), (44, 44, false)
    ], hotCommentIndices: [3, 4])
    #expect(detail.replies.map(\.id) == [44, 2])
    #expect(detail.replies.first?.hot == true)
}

@Test func adjacentPagesMergeAroundTheOpeningFloorOnlyOnce() throws {
    let middle = try threadForDisplay([(20, 20, false), (21, 21, false)], page: 2, total: 3)
    var pages = ThreadPages(middle)
    let first = try threadForDisplay([(1, 0, false), (2, 1, false), (2, 1, false), (20, 20, false)], total: 3)
    let last = try threadForDisplay([(21, 21, false), (22, 22, false)], page: 3, total: 2)
    #expect(pages.merge(first, requestedPage: 1)?.map(\.id) == [1, 2])
    #expect(pages.merge(last, requestedPage: 3)?.map(\.id) == [22])
    #expect(pages.loaded == 1...3)
    #expect(pages.total == 3)
    #expect(pages.detail.comments.map(\.id) == [1, 2, 20, 21, 22])
    #expect(pages.merge(last, requestedPage: 3) == nil)
}

@Test func invalidOrUnrelatedPagesLeaveTheReadingPositionAlone() throws {
    var pages = ThreadPages(try threadForDisplay([(20, 20, false)], page: 2, total: 4))
    for (postID, page, requested) in [(88, 3, 3), (42, 1, 3), (42, 4, 4), (42, 0, 0)] {
        let response = try threadForDisplay([(1, 0, false)], postID: postID, page: page, total: 4)
        #expect(pages.merge(response, requestedPage: requested) == nil)
    }
    #expect(pages.loaded == 2...2)
    #expect(pages.detail.comments.map(\.id) == [20])
}

private func threadForDisplay(_ comments: [(id: Int, floor: Int, pinned: Bool)], hotCommentIndices: Set<Int> = [],
                              postID: Int = 42, page: Int = 1, total: Int = 1) throws -> PostDetail {
    let url = try #require(Bundle.module.url(forResource: "thread", withExtension: "json", subdirectory: "Fixtures"))
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let original = try #require((object["comments"] as? [[String: Any]])?.first)
    object["postId"] = postID
    object["postPage"] = page
    object["postPageCount"] = total
    object["comments"] = comments.enumerated().map { index, value in
        var comment = original
        comment["commentId"] = value.id
        comment["floorIndex"] = value.floor
        comment["pined"] = value.pinned
        comment["hot"] = hotCommentIndices.contains(index)
        return comment
    }
    return try JSONDecoder().decode(PostDetail.self, from: JSONSerialization.data(withJSONObject: object))
}
