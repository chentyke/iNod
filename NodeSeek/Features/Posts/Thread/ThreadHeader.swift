import NodeSeekCore
import SwiftUI

struct ThreadHeader: View {
    let post: PostSummary
    let detail: PostDetail?
    let createdDate: Date?
    let showsRank: Bool
    /// The Mac has no floating author bar above the post, so the author leads the line under the title.
    var showsAuthor = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var categoryTitle: String { detail?.categoryWord ?? post.category }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        VStack(alignment: .leading, spacing: 16) {
            Text(detail?.title ?? post.title).font(.title2.bold()).foregroundStyle(Color.seekInk)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            layout {
                if showsAuthor { author }
                if !categoryTitle.isEmpty {
                    SeekCategoryLabel(title: categoryTitle, category: detail?.category ?? post.categoryKey)
                        .fixedSize()
                }
                if let date = createdDate ?? detail?.comments.first(where: { $0.floorIndex == 0 })?.time.date {
                    PostTimestamp(date: date)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if showsRank, let rank = detail?.rank ?? post.rank, rank > 0 {
                    PostRankLabel(rank: rank).font(.footnote)
                }
            }
            Divider().overlay(Color.seekHairline)
        }.padding(.horizontal, 20).padding(.top, 20)
    }

    private var authorName: String { detail?.op.name ?? post.author }

    @ViewBuilder private var author: some View {
        let label = HStack(spacing: 8) {
            AvatarView(name: authorName, url: detail?.op.avatarURL ?? post.avatarURL, size: 24)
            Text(authorName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.seekInk).lineLimit(1)
        }
        if let id = detail?.op.uid ?? post.authorID {
            NavigationLink(value: MemberDestination.profile(id)) { label.contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityLabel("查看 \(authorName) 的主页")
        } else if !authorName.isEmpty {
            label
        }
    }
}
