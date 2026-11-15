import SwiftUI

/// Sizes shared by the reply footer and its reaction dock, chosen so the card's spacing stays even.
enum DockMetrics {
    /// The folded dock's height, which is also the footer row's height.
    static let foldedHeight: CGFloat = 22
    /// The opened dock's height; its items are this tall and `itemWidth` wide.
    static let openHeight: CGFloat = 30
    static let itemWidth: CGFloat = 36
    /// The card's bottom padding, and the folded dock's gap to the card's side and bottom.
    static let cardInset: CGFloat = 12
    /// The space between the reply's text and the footer row.
    static let bodyGap: CGFloat = 8
    /// The opened dock's gap to the card's side, its bottom, and the text above, all the same.
    static var openMargin: CGFloat { (cardInset + foldedHeight + bodyGap - openHeight) / 2 }
    /// How far the opened dock sits below the footer row's centre to keep `openMargin` even above and below.
    static var openDrop: CGFloat { (cardInset + foldedHeight / 2) - (openMargin + openHeight / 2) }
}

/// One reaction in the folded dock: a colored dot, with its count once there is one.
struct CommentReactionDot: View {
    let tint: Color
    let count: Int?
    var isSelected = false

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(tint.opacity(isSelected ? 0.85 : 0.38))
                .frame(width: 8, height: 8)
                .overlay { if isSelected { Circle().stroke(tint.opacity(0.2), lineWidth: 3).padding(-2) } }
            if let count, count > 0 {
                Text(count.formatted())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? tint : Color.secondary)
            }
        }
        .monospacedDigit()
    }
}

/// A reaction in the opened dock: tinted icon, count only when there is one, and a soft tint once chosen.
struct CommentReactionPill: View {
    let symbol: String
    let count: Int?
    let tint: Color
    var isSelected = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint.opacity(isSelected ? 1 : 0.75))
            if let count, count > 0 {
                Text(count.formatted()).foregroundStyle(isSelected ? tint : Color.secondary)
            }
        }
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(minWidth: DockMetrics.itemWidth, minHeight: DockMetrics.openHeight)
        .background { if isSelected { Capsule().fill(tint.opacity(0.1)).padding(3) } }
        .contentShape(.rect)
    }
}

/// A neutral icon for reply and the overflow menu inside the opened dock.
struct CommentToolButtonLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: DockMetrics.itemWidth, height: DockMetrics.openHeight)
            .contentShape(.rect)
    }
}
