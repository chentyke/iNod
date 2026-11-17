import NodeSeekCore
import SwiftUI

struct ImageGallery: Identifiable, Sendable {
    struct Item: Sendable {
        let url: URL
        let alt: String

        var label: Text { Text(alt.isEmpty ? "帖子图片" : alt) }
    }

    let id = UUID()
    let items: [Item]
    let startIndex: Int
    let initialImage: CGImage

    func adding(before: [Item], after: [Item]) -> Self {
        Self(items: before + items + after, startIndex: before.count + startIndex, initialImage: initialImage)
    }

    typealias ReplyImages = [Int: [Item]]

    static func prepareReplyImages(_ replies: [ForumComment]) -> Task<ReplyImages, Never> {
        Task.detached(priority: .utility) {
            var result: ReplyImages = [:]
            for reply in replies {
                guard !Task.isCancelled else { return [:] }
                let items = images(in: reply.markdown)
                if !items.isEmpty { result[reply.id] = items }
            }
            return result
        }
    }

    func includingReplies(_ replyIDs: [Int], at index: Int,
                          from pages: [Task<ReplyImages, Never>]) async -> Self {
        var byReply: ReplyImages = [:]
        for page in pages {
            byReply.merge(await page.value) { first, _ in first }
        }
        return adding(before: replyIDs[..<index].flatMap { byReply[$0] ?? [] },
                      after: replyIDs[(index + 1)...].flatMap { byReply[$0] ?? [] })
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
