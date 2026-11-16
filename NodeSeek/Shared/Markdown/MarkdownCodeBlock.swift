import NodeSeekCore
import SwiftUI

struct MarkdownCodeBlock: View {
    private let content: AttributedString
    private let isTerminal: Bool

    init(text: String) {
        isTerminal = text.contains("\u{1B}")
        var content = AttributedString()
        for run in ANSIText.parse(text) {
            var part = AttributedString(run.text)
            var font = Font.system(.footnote, design: .monospaced)
            if run.style.bold { font = font.bold() }
            if run.style.italic { font = font.italic() }
            part.font = font
            if let color = run.style.foreground { part.foregroundColor = Self.color(color) }
            if let color = run.style.background { part.backgroundColor = Self.color(color) }
            if run.style.underlined { part.underlineStyle = .single }
            content.append(part)
        }
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal) {
            Text(content)
                .foregroundStyle(isTerminal ? Color(white: 0.9) : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(14)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isTerminal ? Color(white: 0.1) : Color.seekTray.opacity(0.65), in: .rect(cornerRadius: 12))
    }

    private static func color(_ color: ANSIColor) -> Color {
        switch color {
        case .rgb(let red, let green, let blue):
            return Color(red: Double(min(max(red, 0), 255)) / 255,
                  green: Double(min(max(green, 0), 255)) / 255,
                  blue: Double(min(max(blue, 0), 255)) / 255)
        case .indexed(let index):
            if (0..<16).contains(index) {
                let palette: [UInt32] = [0x202020, 0xD84A4A, 0x62B85C, 0xD2AF4B, 0x658DDF, 0xBD70CF, 0x4DB8BD, 0xDDDDDD,
                                         0x777777, 0xFF7777, 0x8ADC80, 0xF4D77B, 0x8BB5FF, 0xE59AF5, 0x86E2E6, 0xFFFFFF]
                let hex = palette[index]
                return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
            }
            if (16..<232).contains(index) {
                let value = index - 16
                let levels = [0, 95, 135, 175, 215, 255]
                return Self.color(.rgb(levels[value / 36], levels[(value / 6) % 6], levels[value % 6]))
            }
            if (232..<256).contains(index) {
                return Color(white: Double(8 + (index - 232) * 10) / 255)
            }
            return Color(white: 0.9)
        }
    }
}
