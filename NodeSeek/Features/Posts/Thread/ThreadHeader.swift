import NodeSeekCore
import SwiftUI

struct ThreadHeader: View {
    let post: PostSummary
    let detail: PostDetail?
    let createdDate: Date?
    let showsRank: Bool
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
}
