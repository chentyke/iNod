import NodeSeekCore
import SwiftUI

struct ConversationTimeline: View {
    let messages: [DirectMessage]
    let userID: Int
    @Environment(\.calendar) private var calendar

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                let date = ForumDate.parse(message.createdAt)
                let previous = messages.indices.contains(index - 1) ? messages[index - 1] : nil
                let next = messages.indices.contains(index + 1) ? messages[index + 1] : nil
                let previousDate = previous.flatMap { ForumDate.parse($0.createdAt) }
                let joinsPrevious = joins(message, date, previous, previousDate)
                let joinsNext = joins(message, date, next, next.flatMap { ForumDate.parse($0.createdAt) })

                if let date, previousDate.map({ calendar.isDate($0, inSameDayAs: date) }) != true {
                    Text(date, format: dayStyle(for: date))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, index == 0 ? 0 : 16)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                }
                MessageBubble(message: message, own: message.senderID == userID, date: date,
                              joinsPrevious: joinsPrevious, joinsNext: joinsNext)
                    .padding(.top, joinsPrevious ? 2 : (index == 0 ? 0 : 6))
                    .id(message.id)
            }
            Color.clear.frame(height: 1).id("conversation-bottom").accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func joins(_ message: DirectMessage, _ date: Date?, _ neighbor: DirectMessage?, _ neighborDate: Date?) -> Bool {
        guard message.senderID == neighbor?.senderID, let date, let neighborDate else { return false }
        return calendar.isDate(date, inSameDayAs: neighborDate) && abs(date.timeIntervalSince(neighborDate)) <= 300
    }

    private func dayStyle(for date: Date) -> Date.FormatStyle {
        calendar.isDate(date, equalTo: .now, toGranularity: .year) ? .dateTime.month().day() : .dateTime.year().month().day()
    }
}
