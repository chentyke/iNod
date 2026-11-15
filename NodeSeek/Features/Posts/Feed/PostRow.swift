import NodeSeekCore
import SwiftUI

struct PostRow: View {
    let post: PostSummary
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize: CGFloat = 22

    static let cornerRadius: CGFloat = 22
    static let listVerticalInset: CGFloat = 6
    private var date: Date? { ISO8601DateFormatter.nodeSeek.date(from: post.activityDate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            title
                .font(.headline).foregroundStyle(Color.seekInk)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            PostMetadata(post: post, placement: .card(date))
        }
        .padding(16)
        // In the pinned carousel every card takes the tallest card's height; centring keeps the
        // spare height split evenly above and below instead of opening a gap under a short title.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.seekCard, in: .rect(cornerRadius: Self.cornerRadius))
        .contentShape(.rect(cornerRadius: Self.cornerRadius))
        .contentShape(.contextMenuPreview, .rect(cornerRadius: Self.cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var title: some View {
        if post.pinned {
            Text(post.title).lineLimit(2)
        } else {
            Text(post.title).lineLimit(typeSize.isAccessibilitySize ? nil : 3)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AvatarView(name: post.author, url: post.avatarURL, size: min(avatarSize, 32))
            Text(post.author).font(.subheadline.weight(.semibold)).foregroundStyle(Color.seekInk).lineLimit(1)
            // Read the pin together with the author, not alone in the corner.
            if post.pinned {
                PostPinLabel()
            }
            Spacer(minLength: 0)
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if post.pinned { parts.append("置顶") }
        parts.append(post.title)
        if let rank = post.rank, rank > 0 { parts.append(PostRankLabel.title(for: rank)) }
        if !post.author.isEmpty { parts.append(post.author) }
        if !post.category.isEmpty { parts.append(post.category) }
        if let date { parts.append(date.formatted(.relative(presentation: .named))) }
        parts.append("\(post.replies) 条回复")
        if post.views > 0 { parts.append("\(post.views) 次浏览") }
        return parts.joined(separator: "，")
    }
}

extension View {
    /// List row chrome for a `PostRow` card floating on the canvas.
    func postCardRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: PostRow.listVerticalInset, leading: 16,
                                      bottom: PostRow.listVerticalInset, trailing: 16))
    }
}
