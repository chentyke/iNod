import NodeSeekCore
import SwiftUI

struct ImageGallery: Identifiable {
    struct Item {
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
