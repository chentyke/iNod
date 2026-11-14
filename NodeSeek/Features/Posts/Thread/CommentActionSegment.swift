import SwiftUI

struct CommentActionSegment: ViewModifier {
    let tint: Color
    var isSelected = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(tint)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                LinearGradient(colors: [tint.opacity(isSelected ? 0.12 : 0.04),
                                        tint.opacity(isSelected ? 0.22 : 0.10)],
                               startPoint: .top, endPoint: .bottom)
            }
            .contentShape(.rect)
    }
}
