import NodeSeekCore
import SwiftUI

struct ImageGallery: Identifiable, Sendable {
    struct Attribution: Sendable {
        let author: String
        let floor: Int
        let avatarURL: URL?
        let date: Date?
        let excerpt: String?

        init(_ comment: ForumComment, blocks: [MarkdownBlock]) {
            author = comment.poster.name
            floor = comment.floorIndex
            avatarURL = comment.poster.avatarURL
            date = ForumDate.parse(comment.time.createdDate)
            excerpt = blocks.lazy.compactMap { block -> String? in
                let text: String
                switch block {
                case .text(let value), .heading(let value): text = value
                case .list(let items, _):
                    guard let first = items.first else { return nil }
                    text = first
                default: return nil
                }
                let plain = ForumText.attributed(String(text.prefix(256))).characters
                let line = String(plain).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                return line.isEmpty ? nil : line
            }.first
        }
    }

    struct Item: Sendable {
        let url: URL
        let alt: String
        var attribution: Attribution?

        var label: String { alt.isEmpty ? "帖子图片" : alt }

        func attributed(to source: Attribution) -> Self {
            Item(url: url, alt: alt, attribution: source)
        }
    }

    let id = UUID()
    var items: [Item]
    let startIndex: Int
    let initialImage: CGImage
    let source: Namespace.ID

    func adding(before: [Item], after: [Item]) -> Self {
        Self(items: before + items + after, startIndex: before.count + startIndex, initialImage: initialImage, source: source)
    }

    typealias CommentImages = [Int: [Item]]

    static func prepareCommentImages(_ comments: [ForumComment]) -> Task<CommentImages, Never> {
        Task.detached(priority: .utility) {
            var result: CommentImages = [:]
            for comment in comments {
                guard !Task.isCancelled else { return [:] }
                guard comment.markdown.contains("![") else { continue }
                let blocks = MarkdownBlock.parse(comment.markdown)
                let items = images(in: blocks)
                guard !items.isEmpty else { continue }
                let source = Attribution(comment, blocks: blocks)
                result[comment.id] = items.map { $0.attributed(to: source) }
            }
            return result
        }
    }

    func includingComments(_ commentIDs: [Int], at index: Int, openedFrom comment: ForumComment,
                          from pages: [Task<CommentImages, Never>]) async -> Self {
        var byComment: CommentImages = [:]
        for page in pages {
            byComment.merge(await page.value) { first, _ in first }
        }
        let origin = byComment[comment.id]?.first?.attribution ?? Attribution(comment, blocks: [])
        var opened = self
        opened.items = items.map { $0.attributed(to: origin) }
        return opened.adding(before: commentIDs[..<index].flatMap { byComment[$0] ?? [] },
                      after: commentIDs[(index + 1)...].flatMap { byComment[$0] ?? [] })
    }

    static func images(in blocks: some Sequence<MarkdownBlock>) -> [Item] {
        blocks.flatMap { block -> [Item] in
            switch block {
            case .image(let alt, let url): [Item(url: url, alt: alt)]
            case .tabs(let tabs): tabs.flatMap { images(in: $0.markdown) }
            case .callout(let callout): images(in: callout.markdown)
            default: []
            }
        }
    }

    static func images(in markdown: String) -> [Item] {
        guard markdown.contains("![") else { return [] }
        return images(in: MarkdownBlock.parse(markdown))
    }
}
