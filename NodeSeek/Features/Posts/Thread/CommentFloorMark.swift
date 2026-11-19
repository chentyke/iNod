import SwiftUI

/// The floor number, followed by a pinned or hot badge when the reply has one.
struct CommentFloorMark: View {
    let floor: Int
    let isPinned: Bool
    let isHot: Bool

    private var spokenLabel: String {
        let kind = isPinned ? "楼主置顶，" : isHot ? "热门评论，" : ""
        return "\(kind)第 \(floor) 楼"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("#\(floor)")
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            if isPinned { CommentBadge(title: "置顶", symbol: .inkPinnedReply, tint: .seekGreen) }
            else if isHot { CommentBadge(title: "热门", symbol: .inkHotReply, tint: .red) }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }
}

/// A small tinted tag, such as 楼主 or 置顶.
struct CommentBadge: View {
    let title: String
    var symbol: ImageResource?
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            if let symbol { Image(symbol).imageScale(.small) }
            Text(title)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(tint.opacity(0.12), in: .capsule)
        .lineLimit(1)
        .fixedSize()
    }
}
