import SwiftUI

struct ReplyQuoteHeader: View {
    let target: ThreadReplyTarget
    var excerptLines = 1
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(.inkQuoteReply)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.seekGreen)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: target.name).fontWeight(.semibold).lineLimit(1)
                    Text(verbatim: target.floor == 0 ? "楼主" : "#\(target.floor)")
                        .foregroundStyle(.secondary).fixedSize()
                }
                if let excerpt = target.excerpt, !excerpt.isEmpty {
                    Text(verbatim: excerpt).lineLimit(excerptLines).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRemove) {
                Image(.inkRemoveQuote)
                    .foregroundStyle(Color.seekButtonIcon)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除引用")
        }
        .accessibilityElement(children: .contain)
    }
}
