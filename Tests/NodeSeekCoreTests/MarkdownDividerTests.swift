import NodeSeekCore
import Testing

@Test(arguments: ["---", "***", "___", "------------", "****", "_____", "- - -", "*\t* *", "  _ _ _ \t"])
func markdownRecognizesDividersBetweenParagraphs(_ divider: String) {
    #expect(MarkdownBlock.parse("上文\n\n\(divider)\n\n下文") == [.text("上文"), .divider, .text("下文")])
}

@Test(arguments: ["- - -", "* * *"])
func markdownKeepsSpacedDividersBetweenLists(_ divider: String) {
    #expect(MarkdownBlock.parse("- 第一项\n\(divider)\n- 第二项") == [
        .list(items: ["第一项"], ordered: false), .divider, .list(items: ["第二项"], ordered: false)
    ])
}

@Test(arguments: ["--", "**", "__", "-*_", "--- 文字", "`---`", #"\---"#])
func markdownKeepsDividerLikeText(_ text: String) {
    #expect(MarkdownBlock.parse(text) == [.text(text)])
}

@Test func markdownKeepsDividerMarkersInsideCodeAndTableRows() {
    #expect(MarkdownBlock.parse("```\n----------\n* * *\n```") == [.code("----------\n* * *")])
    #expect(MarkdownBlock.parse("| A | B |\n| --- | --- |\n| ------ | * * * |") == [
        .table([["A", "B"], ["------", "* * *"]])
    ])
}
