import SwiftUI

struct ImageSourceButton: View {
    let source: ImageGallery.Attribution
    let caption: String?
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.calendar) private var calendar

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                AvatarView(name: source.author, url: source.avatarURL, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    let header = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                    header {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: source.author).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(source.floor == 0 ? "正文" : "#\(source.floor)")
                                .font(.footnote.monospacedDigit()).foregroundStyle(.primary.opacity(0.74))
                                .fixedSize()
                        }
                        if let date = source.date {
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                            dateLabel(date).font(.footnote).foregroundStyle(.primary.opacity(0.74))
                        }
                    }
                    if let caption {
                        Text(verbatim: caption)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: 440, alignment: .leading)
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .accessibilityHint(source.floor == 0 ? "跳转到正文" : "跳转到这条评论")
        .accessibilityIdentifier("image-gallery-attribution")
    }

    private func dateLabel(_ date: Date) -> Text {
        if calendar.isDateInToday(date) { return Text(date, format: .dateTime.hour().minute()) }
        let style = Date.FormatStyle.dateTime.month().day()
        return Text(date, format: calendar.isDate(date, equalTo: .now, toGranularity: .year) ? style : style.year())
    }
}
