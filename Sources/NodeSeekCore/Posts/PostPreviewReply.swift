import Foundation

public struct PostPreviewReply: Identifiable, Sendable {
    public let id: Int
    public let author: String
    public let blocked: Bool
    public let snippet: String

    public static func select(from replies: [ForumComment]) -> [Self] {
        select(from: replies, summarizing: snippet)
    }

    static func select(from replies: [ForumComment], summarizing: (String) -> String) -> [Self] {
        var previews: [Self] = []
        for reply in replies {
            let snippet = summarizing(reply.markdown)
            guard !snippet.isEmpty else { continue }
            previews.append(Self(id: reply.id, author: reply.poster.name, blocked: reply.blocked, snippet: snippet))
            if previews.count == 3 { break }
        }
        return previews
    }

    /// A reply's own words: quoted floors and sticker codes are left out.
    private static func snippet(_ markdown: String) -> String {
        let lines = markdown.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
        return InlineContent.parse(lines.joined(separator: " "))
            .compactMap { if case .text(let text) = $0 { text } else { nil } }
            .joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
