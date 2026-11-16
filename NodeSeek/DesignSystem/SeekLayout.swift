import SwiftUI

/// Sizes shared by pages that must read the same on an iPhone, an iPad and a Mac window.
enum SeekLayout {
    /// The widest a card grows. Wider windows centre one column instead of stretching lines edge to edge.
    static let readableWidth: CGFloat = 760
    /// The gap between a card and the window edge.
    static let gutter: CGFloat = 16
    /// The widest a screen-wide column grows, gutters included. Bars above and below the cards use it
    /// so they line up with the cards.
    static let columnWidth = readableWidth + 2 * gutter

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

extension View {
    /// Centres a list or scroll view's content in a readable column once the window is wider than one.
    ///
    /// Content margins also reach scroll views nested inside the content, so a horizontal scroll view
    /// inside a card sets its horizontal margins back with `contentMargins(.horizontal, 0, for: .scrollContent)`.
    func readableContentMargins(_ style: ReadableMargin = .replacesInset) -> some View {
        modifier(ReadableContentMargins(style: style))
    }

    /// Keeps a bar that floats over a scroll view as wide as the column of cards under it.
    func readableColumn() -> some View {
        frame(maxWidth: SeekLayout.columnWidth).frame(maxWidth: .infinity)
    }
}

private struct ReadableContentMargins: ViewModifier {
    let style: ReadableMargin
    @State private var margins = SideMargins()

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, margins.leading, for: .scrollContent)
            .contentMargins(.trailing, margins.trailing, for: .scrollContent)
            .onGeometryChange(for: SideMargins.self) { proxy in
                // A sidebar beside the page (iPad, Mac) sits in the safe area, and the scroll view runs on under it.
                // Setting margins replaces that safe-area inset, so add it back on its side.
                let margin = SeekLayout.sideMargin(forWidth: proxy.size.width, style)
                return SideMargins(leading: margin + proxy.safeAreaInsets.leading,
                                   trailing: margin + proxy.safeAreaInsets.trailing)
            } action: { margins = $0 }
    }
}

private struct SideMargins: Equatable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
}
