import NodeSeekCore
import SwiftUI

struct MarkdownContent<Embedded: View>: View {
    let markdown: String
    var spacing: CGFloat = 16
    var expandsText = true
    var trailingLabel: Text?
    var loadsBlocksOnScroll = false
    var onOpenImages: ((ImageGallery) -> Void)?
    @ViewBuilder var embedded: (MarkdownBlock) -> Embedded
    @State private var gallery: ImageGallery?

    var body: some View {
        let blocks = MarkdownBlock.parse(markdown)
        VStack(alignment: .trailing, spacing: 3) {
            if loadsBlocksOnScroll, blocks.count > 24 {
                LazyVStack(alignment: .leading, spacing: spacing) { blockViews(blocks) }
            } else {
                VStack(alignment: .leading, spacing: spacing) { blockViews(blocks) }
            }
            if let trailingLabel {
                switch blocks.last {
                case .text, .heading, .quote, .list: EmptyView()
                default: trailingLabel
                }
            }
        }
        .fullScreenCover(item: $gallery) { ImageViewer(gallery: $0) }
    }

    private func blockViews(_ blocks: [MarkdownBlock]) -> some View {
        ForEach(blocks.indices, id: \.self) { index in
            let label = index == blocks.count - 1 ? trailingLabel : nil
            blockView(blocks[index], label: label) { opened in
                let images = opened.adding(before: ImageGallery.images(in: blocks[..<index]),
                                           after: ImageGallery.images(in: blocks[(index + 1)...]))
                if let onOpenImages { onOpenImages(images) }
                else { gallery = images }
            }
        }
    }

    @ViewBuilder private func blockView(_ block: MarkdownBlock, label: Text?,
                                        openImages: @escaping (ImageGallery) -> Void) -> some View {
        switch block {
        case .text(let text):
            InlineStickerText(markdown: text, expands: expandsText, trailingLabel: label)
        case .heading(let text):
            InlineStickerText(markdown: text, expands: false, trailingLabel: label, font: .title3.bold(), lineSpacing: 0)
        case .code(let text): MarkdownCodeBlock(text: text)
        case .image(let alt, let url): ForumImageView(url: url, alt: alt, onOpenImages: openImages)
        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                // design-check: allow 引用块左侧 3 点宽的竖线
                RoundedRectangle(cornerRadius: 2).fill(Color.seekGreen.opacity(0.5)).frame(width: 3)
                InlineStickerText(markdown: text, expands: expandsText, trailingLabel: label)
                    .foregroundStyle(.secondary).padding(.vertical, 4)
            }.fixedSize(horizontal: false, vertical: true)
        case .divider: Divider()
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.indices, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ordered ? "\(item + 1)." : "•").foregroundStyle(.secondary)
                        InlineStickerText(markdown: items[item], expands: expandsText,
                                          trailingLabel: item == items.count - 1 ? label : nil)
                    }
                }
            }
        case .table(let rows): MarkdownTable(rows: rows)
        case .vote, .stardust: embedded(block)
        case .tabs(let tabs):
            MarkdownTabsView(tabs: tabs, loadsBlocksOnScroll: loadsBlocksOnScroll, onOpenImages: openImages, embedded: embedded)
        case .callout(let callout):
            MarkdownCalloutView(callout: callout, loadsBlocksOnScroll: loadsBlocksOnScroll, onOpenImages: openImages, embedded: embedded)
        }
    }
}

private struct MarkdownTable: View {
    let rows: [[String]]
    @Environment(\.forumDocumentURL) private var documentURL
    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(0..<(rows.map(\.count).max() ?? 0), id: \.self) { column in
                            let text = ForumText.attributed(column < rows[row].count ? rows[row][column] : "", baseURL: documentURL)
                            TextWithTrailingLabel(text: Text(text).font(.subheadline.weight(row == 0 ? .semibold : .regular)),
                                                  label: nil, hasLinks: text.runs.contains { $0.link != nil })
                                .padding(12).frame(minWidth: 100, maxWidth: 260, alignment: .leading)
                                .background(Color.primary.opacity(row == 0 ? 0.07 : (row.isMultiple(of: 2) ? 0.025 : 0)))
                                .overlay(alignment: .bottom) { Divider() }
                        }
                    }
                }
            }
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .clipShape(.rect(cornerRadius: 10))
    }
}
