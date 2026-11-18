import NodeSeekCore
import SwiftUI

/// Sizes shared by pages that must read the same on an iPhone, an iPad and a Mac window.
enum SeekLayout {
    /// The widest a card grows. Wider windows centre one column instead of stretching lines edge to edge.
    static let readableWidth = CGFloat(FeedSplitLayout.readableWidth)
    /// The gap between a card and the window edge.
    static let gutter = CGFloat(FeedSplitLayout.gutter)
    /// The widest a screen-wide column grows, gutters included. Bars above and below the cards use it
    /// so they line up with the cards.
    static let columnWidth = readableWidth + 2 * gutter
    /// Hairline rule between the iPad feed column and the thread column beside it.
    static let splitDividerWidth = CGFloat(FeedSplitLayout.dividerWidth)

    static func usesFeedSplit(forWidth width: CGFloat, supportsSplit: Bool, isCompact: Bool) -> Bool {
        FeedSplitLayout.usesSplit(width: Double(width), supportsSplit: supportsSplit, isCompact: isCompact)
    }

    static func feedPaneWidth(forTotalWidth totalWidth: CGFloat) -> CGFloat {
        CGFloat(FeedSplitLayout.feedPaneWidth(forTotalWidth: Double(totalWidth)))
    }

    /// Space on each side of a scroll view's content so its cards keep to `readableWidth`.
    static func sideMargin(forWidth width: CGFloat, _ style: ReadableMargin) -> CGFloat {
        switch style {
        case .keepsGutter:
            max(0, ((width - columnWidth) / 2).rounded(.down))
        case .replacesInset:
            // The margin stands in for the list's own inset, so it never drops below one gutter.
            max(gutter, ((width - readableWidth) / 2).rounded(.down))
        }
    }
}

/// How a scroll view's content sits inside the readable-width margins.
enum ReadableMargin {
    /// A grouped list or form uses the margin in place of its own section inset, so the margin is at least
    /// one `gutter` even on an iPhone.
    case replacesInset
    /// A plain list's row insets or a scroll view's padding add the usual `gutter` inside the margin,
    /// so the margin is 0 until the window is wider than `columnWidth`.
    case keepsGutter
}

/// The kind of scroll view that gets the readable-width margins. A sidebar beside the page (iPad, Mac) sits in
/// the scroll view's safe area, and the two kinds treat that safe area differently.
enum ReadableScroller {
    /// A `List` or `Form`. Its margins replace the safe-area inset, so they add the sidebar's inset back in.
    case list
    /// A `ScrollView`. It keeps its safe-area inset and adds the margins inside it, so they leave the sidebar out.
    case scrollView
}

extension View {
    /// Centres a list or scroll view's content in a readable column once the window is wider than one.
    ///
    /// Content margins also reach scroll views nested inside the content, so a horizontal scroll view
    /// inside a card sets its horizontal margins back with `contentMargins(.horizontal, 0, for: .scrollContent)`.
    func readableContentMargins(_ style: ReadableMargin = .replacesInset, in scroller: ReadableScroller = .list) -> some View {
        modifier(ReadableContentMargins(style: style, scroller: scroller))
    }

    /// Keeps a bar that floats over a scroll view as wide as the column of cards under it.
    func readableColumn() -> some View {
        frame(maxWidth: SeekLayout.columnWidth).frame(maxWidth: .infinity)
    }
}

private struct ReadableContentMargins: ViewModifier {
    let style: ReadableMargin
    let scroller: ReadableScroller
    @State private var margins = SideMargins()

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, margins.leading, for: .scrollContent)
            .contentMargins(.trailing, margins.trailing, for: .scrollContent)
            .onGeometryChange(for: SideMargins.self) { proxy in
                // A sidebar beside the page (iPad, Mac) sits in the safe area, and the scroll view runs on under it.
                // A list's margins replace that safe-area inset, so add it back on its side. A `ScrollView` keeps
                // the inset and adds the margins to it; adding it again pushed the cards off centre by a sidebar's width.
                let margin = SeekLayout.sideMargin(forWidth: proxy.size.width, style)
                guard scroller == .list else { return SideMargins(leading: margin, trailing: margin) }
                return SideMargins(leading: margin + proxy.safeAreaInsets.leading,
                                   trailing: margin + proxy.safeAreaInsets.trailing)
            } action: { margins = $0 }
    }
}

private struct SideMargins: Equatable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
}
