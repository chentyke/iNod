import SwiftUI

struct SeekPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Gently sinks a card while it is pressed.
struct SeekCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SeekPressStyle {
    static var seekRow: SeekPressStyle { SeekPressStyle() }
}

extension ButtonStyle where Self == SeekCardPressStyle {
    static var seekCard: SeekCardPressStyle { SeekCardPressStyle() }
}
