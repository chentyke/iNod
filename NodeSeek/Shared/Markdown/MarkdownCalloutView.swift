import NodeSeekCore
import SwiftUI

/// 官网 `> [!note]` 提示块：和引用一样靠左侧竖线区分，只有小图标带类型颜色；可收起的标题点一下展开。
struct MarkdownCalloutView<Embedded: View>: View {
    let callout: MarkdownCallout
    var loadsBlocksOnScroll = false
    let onOpenImages: (ImageGallery) -> Void
    @ViewBuilder var embedded: (MarkdownBlock) -> Embedded
    @State private var isExpanded: Bool
    @Environment(\.forumDocumentURL) private var documentURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(callout: MarkdownCallout, loadsBlocksOnScroll: Bool = false,
         onOpenImages: @escaping (ImageGallery) -> Void,
         @ViewBuilder embedded: @escaping (MarkdownBlock) -> Embedded) {
        self.callout = callout
        self.loadsBlocksOnScroll = loadsBlocksOnScroll
        self.onOpenImages = onOpenImages
        self.embedded = embedded
        _isExpanded = State(initialValue: callout.folding != .collapsed)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // design-check: allow 提示块左侧 3 点宽的竖线，和引用块一致
            RoundedRectangle(cornerRadius: 2).fill(callout.kind.tint.opacity(0.5)).frame(width: 3)
            VStack(alignment: .leading, spacing: 10) {
                if callout.folding == .none {
                    header
                } else {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { isExpanded.toggle() }
                    } label: { header.contentShape(.rect) }
                    .buttonStyle(.plain)
                    .accessibilityValue(isExpanded ? "已展开" : "已收起")
                    .accessibilityHint(isExpanded ? "收起内容" : "展开内容")
                }
                if isExpanded {
                    MarkdownContent(markdown: callout.markdown, spacing: 12, loadsBlocksOnScroll: loadsBlocksOnScroll,
                                    onOpenImages: onOpenImages, embedded: embedded)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(callout.kind.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(callout.kind.tint)
                .accessibilityHidden(true)
            Text(ForumText.attributed(callout.title ?? callout.kind.defaultTitle, baseURL: documentURL))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            if callout.folding != .none {
                Image(.inkFoldNote)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension MarkdownCallout.Kind {
    var defaultTitle: String {
        switch self {
        case .note: "备注"
        case .tip: "提示"
        case .important: "重要"
        case .warning: "警告"
        case .caution: "注意"
        }
    }

    var symbol: ImageResource {
        switch self {
        case .note: .inkNote
        case .tip: .inkTip
        case .important: .inkImportant
        case .warning: .inkWarning
        case .caution: .inkCaution
        }
    }

    var tint: Color {
        switch self {
        case .note: .blue
        case .tip: .seekGreen
        case .important: .purple
        case .warning: .orange
        case .caution: .red
        }
    }
}
