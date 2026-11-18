import NodeSeekCore
import SwiftUI

struct MessageBubble: View {
    let message: DirectMessage
    let own: Bool
    let date: Date?
    let joinsPrevious: Bool
    let joinsNext: Bool

    var body: some View {
        Group {
            if message.isMarkdown {
                ForumMarkdown(markdown: message.content, spacing: 8, expandsText: false, trailingLabel: time)
            } else {
                let text = Text(ForumText.attributed(plainText, markdown: false))
                TextWithTrailingLabel(text: text, label: time)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .foregroundStyle(Color.seekInk)
        .background {
            bubbleShape.fill(Color.seekCard)
                .overlay { if own { bubbleShape.fill(Color.seekGreen.opacity(0.13)) } }
                #if DEBUG
                // Selectable text widens the bubble's outer accessibility frame on Mac; expose the visual bubble bounds for layout tests.
                .overlay { Color.clear.accessibilityElement().accessibilityIdentifier("message-\(message.id)") }
                #endif
        }
        .frame(maxWidth: 500, alignment: own ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: own ? .trailing : .leading)
        .padding(own ? .leading : .trailing, 52)
    }

    private var plainText: String {
        let content = message.content
        guard let lastCharacter = content.lastIndex(where: { !$0.isNewline }) else { return "" }
        return String(content[...lastCharacter])
    }

    private var time: Text? {
        guard !message.createdAt.isEmpty else { return nil }
        let text = date.map { Text($0, format: .dateTime.hour().minute()) } ?? Text(verbatim: message.createdAt)
        return text.font(.caption).foregroundStyle(.secondary)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        let top: CGFloat = joinsPrevious ? 5 : 16
        let bottom: CGFloat = joinsNext ? 5 : 16
        return .rect(topLeadingRadius: own ? 16 : top,
                     bottomLeadingRadius: own ? 16 : bottom,
                     bottomTrailingRadius: own ? bottom : 16,
                     topTrailingRadius: own ? top : 16)
    }
}
