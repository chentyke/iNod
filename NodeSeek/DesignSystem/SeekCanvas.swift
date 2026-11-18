import SwiftUI

extension EnvironmentValues {
    /// True inside the right pane of a split layout whose outer container already draws the top-left glow.
    @Entry var suppressesCanvasGlow = false
}

struct SeekCanvas: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.suppressesCanvasGlow) private var suppressesCanvasGlow

    var body: some View {
        Color.seekCanvas
            .overlay(alignment: .topLeading) {
                if !reduceTransparency && !suppressesCanvasGlow {
                    // design-check: allow 画布左上角 0.1 不透明度的淡绿光晕，不落在内容上
                    RadialGradient(colors: [Color.seekGreen.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 380)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
