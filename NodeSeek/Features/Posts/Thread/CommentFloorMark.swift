import SwiftUI

struct CommentFloorMark: View {
    let floor: Int
    let isPinned: Bool
    let isHot: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var fontSize = 64.0
    @Environment(\.colorSchemeContrast) private var colorContrast

    private var prefix: String { isPinned ? "📌" : isHot ? "🔥" : "" }
    private var tint: Color { isPinned ? .seekGreen : isHot ? .red : .seekInk }
    private var spokenLabel: String {
        let kind = isPinned ? "楼主置顶，" : isHot ? "热门评论，" : ""
        return "\(kind)第 \(floor) 楼"
    }

    var body: some View {
        Text("\(prefix)#\(floor)")
            .font(.system(size: min(fontSize, 88), weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .opacity(colorContrast == .increased ? 0.35 : 0.08)
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(maxWidth: 240, alignment: .trailing)
            .accessibilityLabel(spokenLabel)
            .allowsHitTesting(false)
    }
}
