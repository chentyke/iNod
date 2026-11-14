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

private func threadForDisplay(_ comments: [(id: Int, floor: Int, pinned: Bool)], hotCommentIndices: Set<Int> = []) throws -> PostDetail {
    let url = try #require(Bundle.module.url(forResource: "thread", withExtension: "json", subdirectory: "Fixtures"))
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let original = try #require((object["comments"] as? [[String: Any]])?.first)
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
