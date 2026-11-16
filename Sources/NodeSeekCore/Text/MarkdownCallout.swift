import Foundation

/// 官网的提示块：引用第一行写 `[!note]`，`-` 表示默认收起，`+` 表示可收起但默认展开。
public struct MarkdownCallout: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable { case note, tip, important, warning, caution }
    public enum Folding: Sendable { case none, collapsed, expanded }

    public let kind: Kind
    /// 作者写的标题；没写时界面按类型显示默认名字。
    public let title: String?
    public let folding: Folding
    public let markdown: String

    public init(kind: Kind, title: String?, folding: Folding, markdown: String) {
        self.kind = kind; self.title = title; self.folding = folding; self.markdown = markdown
    }

    /// `lines` 是去掉 `>` 和其后一个空格的引用内容。和官网一样，标记行后面要紧跟正文，否则仍是普通引用。
    init?(quoteLines lines: [String]) {
        guard lines.count > 1, !lines[1].trimmingCharacters(in: .whitespaces).isEmpty,
              let match = lines[0].trimmingCharacters(in: .whitespaces)
                .firstMatch(of: /^\[!(?<kind>[A-Za-z]+)\](?<fold>[+-]?)(?:\s+(?<title>.*))?$/),
              let kind = Kind(rawValue: match.kind.lowercased()) else { return nil }
        let title = match.title.map { $0.trimmingCharacters(in: .whitespaces) }
        self.init(kind: kind, title: title?.isEmpty == false ? title : nil,
                  folding: match.fold == "-" ? .collapsed : match.fold == "+" ? .expanded : .none,
                  markdown: lines.dropFirst().joined(separator: "\n"))
    }
}
