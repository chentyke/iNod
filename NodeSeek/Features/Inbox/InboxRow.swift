import SwiftUI

struct InboxRow: View {
    let name: String
    let avatarURL: URL?
    let title: String
    let detail: String
    let date: Date?
    let isUnread: Bool
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(name: name, url: avatarURL, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline.weight(isUnread ? .semibold : .regular))
                        .foregroundStyle(Color.seekInk)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !typeSize.isAccessibilitySize { timestamp.fixedSize() }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if typeSize.isAccessibilitySize { timestamp }
            }
            .frame(minHeight: 40, alignment: .center)
        }
        .contentShape(.rect)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 52 }
        .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
        .accessibilityElement(children: .combine)
    }

    private var timestamp: some View {
        HStack(spacing: 6) {
            if let date {
                Text(date, format: dateStyle(for: date))
                    .accessibilityLabel(Text(date, format: .dateTime.year().month().day().hour().minute()))
            }
            if isUnread {
                Circle().fill(Color.seekGreen)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("未读")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func dateStyle(for date: Date) -> Date.FormatStyle {
        let now = Date.now
        guard calendar.isDate(date, equalTo: now, toGranularity: .year) else {
            return .dateTime.year().month(.defaultDigits).day()
        }
        if calendar.isDate(date, inSameDayAs: now) { return .dateTime.hour().minute() }
        if let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)),
           date >= cutoff, date < now {
            return .dateTime.weekday(.abbreviated)
        }
        return .dateTime.month(.defaultDigits).day()
    }
}
