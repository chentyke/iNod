import SwiftUI

struct SeekPillStyle: ButtonStyle {
    var primary = true
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 48)
            .foregroundStyle(isEnabled ? (primary ? Color.seekOnInk : .seekInk) : .secondary)
            .background(isEnabled ? (primary ? Color.seekInk : .seekCard) : .seekTray, in: .capsule)
            .overlay { if !primary { Capsule().strokeBorder(Color.seekHairline.opacity(0.6), lineWidth: 0.5) } }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == SeekPillStyle {
    static var seekPill: SeekPillStyle { SeekPillStyle() }
    static func seekPill(primary: Bool = true, fullWidth: Bool = true) -> SeekPillStyle {
        SeekPillStyle(primary: primary, fullWidth: fullWidth)
    }
}
