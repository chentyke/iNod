import Testing
@testable import NodeSeekCore

@Test func postPreviewSkipsEmptyQuotesAndStickersAndKeepsReplyOrder() {
    let replies = [
        reply(1, "  "),
        reply(17, "  > quoted floor\n First line:ac2054:\nSecond line "),
        reply(2, "> only a quote"),
        reply(8, " :ac2054: ", blocked: true),
        reply(6, "Second reply", blocked: true),
        reply(4, "**Third reply**"),
        reply(9, "Fourth reply")
    ]

    let preview = PostPreviewReply.select(from: replies)

    #expect(preview.map(\.id) == [17, 6, 4])
    #expect(preview.map(\.author) == ["Reader 17", "Reader 6", "Reader 4"])
    #expect(preview.map(\.blocked) == [false, true, false])
    #expect(preview.map(\.snippet) == ["First line Second line", "Second reply", "**Third reply**"])
}

@Test func postPreviewStopsSummarizingAfterTheThirdMatchAndStoresTheResults() {
    let replies = ["quote", "first", "second", "sticker", "third", "later"]
        .enumerated().map { reply($0.offset + 1, $0.element) }
    var summarized: [String] = []

    let preview = PostPreviewReply.select(from: replies) { markdown in
        summarized.append(markdown)
        guard markdown != "quote", markdown != "sticker" else { return "" }
        return "Summary \(summarized.count) for \(markdown)"
    }

    #expect(preview.map(\.id) == [2, 3, 5])
    #expect(preview.map(\.snippet) == ["Summary 2 for first", "Summary 3 for second", "Summary 5 for third"])
    #expect(summarized == ["quote", "first", "second", "sticker", "third"])
}

@Test func postPreviewReturnsAvailableRepliesWhenThereAreFewerThanThree() {
    let preview = PostPreviewReply.select(from: [reply(1, "Only reply"), reply(2, "> a quote")])

    #expect(preview.map(\.snippet) == ["Only reply"])
}

private func reply(_ id: Int, _ markdown: String, blocked: Bool = false) -> ForumComment {
    ForumComment(
        commentId: id,
        floorIndex: id,
        poster: ForumUser(uid: id, name: "Reader \(id)", avatar: nil),
        time: CommentTime(createdDate: "", editedDate: nil),
        markdown: markdown,
        likeCount: 0,
        upvoteCount: 0,
        signature: nil,
        blocked: blocked
    )
}
