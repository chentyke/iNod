import Testing
@testable import NodeSeekCore

@Test func reportTabsKeepCodeImagesAndFollowingContent() {
    let source = """
    开头

    :::: tabs
    ::: tab-item 💻基本信息
    ```ansi
    \u{1B}[32mCPU: AMD\u{1B}[0m
    ```
    :::
    ::: tab-item 🌐网络质量
    ![网络](https://example.com/network.png)
    :::
    ::::

    [NodeQuality链接](https://example.com/report)
    """
    let blocks = MarkdownBlock.parse(source)
    #expect(blocks.count == 3)
    guard case .tabs(let tabs) = blocks[1] else { Issue.record("没有解析出标签分组"); return }
    #expect(tabs.map(\.title) == ["💻基本信息", "🌐网络质量"])
    #expect(MarkdownBlock.parse(tabs[0].markdown) == [.code("\u{1B}[32mCPU: AMD\u{1B}[0m")])
    #expect(MarkdownBlock.parse(tabs[1].markdown).count == 1)
    #expect(blocks.last == .text("[NodeQuality链接](https://example.com/report)"))
}

@Test func tabMarkersInsideCodeStayLiteral() {
    #expect(MarkdownBlock.parse("```\n:::: tabs\n::: tab-item 示例\n::::\n```") == [.code(":::: tabs\n::: tab-item 示例\n::::")])
    let source = ":::: tabs\n::: tab-item 示例\n```\n:::\n::::\n```\n:::\n::::"
    guard case .tabs(let tabs) = MarkdownBlock.parse(source).first else { Issue.record("没有解析出标签分组"); return }
    #expect(MarkdownBlock.parse(tabs[0].markdown) == [.code(":::\n::::")])
}

@Test func incompleteTabGroupKeepsItsContent() {
    let source = ":::: tabs\n::: tab-item 示例\n正文"
    #expect(MarkdownBlock.parse(source) == [.text(source)])
}

@Test func ansiReportsPreserveTextAndResetColors() {
    let runs = ANSIText.parse("CPU: \u{1B}[1;32mAMD\u{1B}[0m 4 cores")
    #expect(runs.map(\.text).joined() == "CPU: AMD 4 cores")
    #expect(runs[1].style.foreground == .indexed(2))
    #expect(runs[1].style.bold)
    #expect(runs[2].style == ANSIStyle())
}

@Test func ansiReportBackgroundsAndBackspacesDoNotLeakControlCharacters() {
    let runs = ANSIText.parse("\u{1B}[41;37m   \u{1B}[0m\u{8}\u{1B}[1;33m|1498\u{1B}[0m")
    #expect(runs.map(\.text).joined() == "  |1498")
    #expect(runs[0].style.background == .indexed(1))
    #expect(runs[1].style.foreground == .indexed(3))
}

@Test func ansiExtendedColorsAndTerminalMetadataAreHandled() {
    let runs = ANSIText.parse("\u{1B}[38;2;10;20;30;48;5;200mRGB\u{1B}[39;49m plain\u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{7}\u{1B}[K")
    #expect(runs.map(\.text).joined() == "RGB plainlink")
    #expect(runs[0].style.foreground == .rgb(10, 20, 30))
    #expect(runs[0].style.background == .indexed(200))
    #expect(runs[1].style == ANSIStyle())
}
