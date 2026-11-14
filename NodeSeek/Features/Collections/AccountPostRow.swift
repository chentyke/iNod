import NodeSeekCore
import SwiftUI

struct AccountPostRow: View {
    let item: AccountPost
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(3)
            if let excerpt = item.excerpt, !excerpt.isEmpty {
                Text(ForumText.attributed(excerpt, markdown: false)).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            if item.floor > 0 || (item.rank ?? 0) > 0 {
                HStack {
                    if item.floor > 0 { Text("#\(item.floor)") }
                    if let rank = item.rank, rank > 0 {
                        PostRankLabel(rank: rank)
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 10)
    }
}
