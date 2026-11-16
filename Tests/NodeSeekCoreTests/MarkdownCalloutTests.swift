import Foundation
import Testing
@testable import NodeSeekCore

@Test func collapsedCalloutsKeepImagesOutOfTheQuoteText() {
    let source = """
    >[!note]- 选项1
    > ![image](https://example.com/first.png)

    >[!note]- 选项2
    >![image](https://example.com/second.png)


     nsapp://vote?id=42

    猜猜看 :ac01:
    """
    #expect(MarkdownBlock.parse(source) == [
        .callout(MarkdownCallout(kind: .note, title: "选项1", folding: .collapsed,
                                 markdown: "![image](https://example.com/first.png)")),
        .callout(MarkdownCallout(kind: .note, title: "选项2", folding: .collapsed,
                                 markdown: "![image](https://example.com/second.png)")),
        .vote(42),
        .text("猜猜看 :ac01:")
    ])
    guard case .callout(let first) = MarkdownBlock.parse(source).first else { return }
    #expect(MarkdownBlock.parse(first.markdown) == [.image(alt: "image", url: URL(string: "https://example.com/first.png")!)])
}

@Test func calloutTypesFoldingAndTitlesMatchWebsite() {
    #expect(MarkdownBlock.parse("> [!TIP]\n> 先备份") == [
        .callout(MarkdownCallout(kind: .tip, title: nil, folding: .none, markdown: "先备份"))
    ])
    #expect(MarkdownBlock.parse("> [!Warning]+ 小心 **数据**\n> 会清空硬盘") == [
        .callout(MarkdownCallout(kind: .warning, title: "小心 **数据**", folding: .expanded, markdown: "会清空硬盘"))
    ])
    #expect(MarkdownBlock.parse("> [!important]\n> 一\n> 二") == [
        .callout(MarkdownCallout(kind: .important, title: nil, folding: .none, markdown: "一\n二"))
    ])
    #expect(MarkdownBlock.parse("> [!caution] 别这样\n> 原因") == [
        .callout(MarkdownCallout(kind: .caution, title: "别这样", folding: .none, markdown: "原因"))
    ])
}

@Test func calloutLookalikesStayPlainQuotes() {
    // 官网只认五种类型，标记后面还要紧跟正文。
    #expect(MarkdownBlock.parse("> [!info]\n> 正文") == [.quote("[!info]\n正文")])
    #expect(MarkdownBlock.parse("> [!note] 只有标题") == [.quote("[!note] 只有标题")])
    #expect(MarkdownBlock.parse("> [!note]\n>\n> 隔了空行") == [.quote("[!note]\n\n隔了空行")])
    #expect(MarkdownBlock.parse("> 普通引用\n> [!note] 不在第一行") == [.quote("普通引用\n[!note] 不在第一行")])
}

@Test func calloutBodiesKeepNestedMarkdown() {
    let source = """
    > [!note] 步骤
    > 1. 安装
    > 2. 运行
    >
    > ```sh
    >   echo hi
    > ```
    后文
    """
    let blocks = MarkdownBlock.parse(source)
    #expect(blocks.count == 2)
    guard case .callout(let callout) = blocks.first else { Issue.record("没有解析出提示块"); return }
    #expect(MarkdownBlock.parse(callout.markdown) == [.list(items: ["安装", "运行"], ordered: true), .code("  echo hi")])
    #expect(blocks.last == .text("后文"))
}
