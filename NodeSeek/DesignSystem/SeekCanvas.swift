import SwiftUI

struct SeekCanvas: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Color.seekCanvas
            .overlay(alignment: .topLeading) {
                if !reduceTransparency {
                    RadialGradient(colors: [Color.seekGreen.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 380)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
