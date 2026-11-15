import SwiftUI

struct ThreadScrollEdgeFade: ViewModifier {
    private let maximumHeight: CGFloat = 28
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let distance = geometry.contentOffset.y + geometry.contentInsets.top
                return min(maximumHeight, max(0, distance))
            } action: { _, distance in
                height = distance
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: height)
                    Color.black
                }
            }
    }
}
