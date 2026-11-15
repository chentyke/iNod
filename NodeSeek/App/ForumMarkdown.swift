import SwiftUI

/// Supplies the forum-specific blocks used by the shared Markdown renderer.
struct ForumMarkdown: View {
    let markdown: String
    var spacing: CGFloat = 16
    var expandsText = true
    var trailingLabel: Text?
    var loadsBlocksOnScroll = false
    var onOpenImages: ((ImageGallery) -> Void)?

    var body: some View {
        MarkdownContent(markdown: markdown, spacing: spacing, expandsText: expandsText, trailingLabel: trailingLabel,
                        loadsBlocksOnScroll: loadsBlocksOnScroll, onOpenImages: onOpenImages) { block in
            switch block {
            case .vote(let id): VoteView(voteID: id)
            case .stardust(let request): StardustRequestView(request: request)
            default: EmptyView()
            }
        }
    }
}
