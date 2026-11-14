import NodeSeekCore
import SwiftUI

struct PostMetadata: View {
    enum Placement {
        case card(Date?)
        case preview
    }

    let post: PostSummary
    var placement: Placement = .preview
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            switch placement {
            case .card(let date):
                cardMetadata(date: date).font(.caption)
            case .preview:
                previewMetadata.font(.footnote)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func cardMetadata(date: Date?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statsAndTime(date: date)
                Spacer(minLength: 0)
                rank
                category
            }
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    statsAndTime(date: date)
                    VStack(alignment: .leading, spacing: 6) {
                        counts(spacing: 12)
                        timestamp(date)
                    }
                }
                if (post.rank ?? 0) > 0 || !post.category.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            rank
                            category
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            rank
                            category
                        }
                    }
                }
            }
        }
    }

    private func statsAndTime(date: Date?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            counts(spacing: 12)
            timestamp(date)
        }
    }

    private var previewMetadata: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            counts(spacing: 16)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            rank
            if post.pinned { PostPinLabel() }
        }
    }

    @ViewBuilder private var rank: some View {
        if let rank = post.rank, rank > 0 { PostRankLabel(rank: rank).fixedSize() }
    }

    @ViewBuilder private var category: some View {
        if !post.category.isEmpty {
            let tint = Color.categoryTint(post.categoryKey)
            Text(post.category)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(tint.opacity(0.12), in: .capsule)
                .fixedSize()
        }
    }

    @ViewBuilder private func timestamp(_ date: Date?) -> some View {
        if let date {
            Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .monospacedDigit().fixedSize()
        }
    }

    private func counts(spacing: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            stat(post.replies, systemImage: "bubble.left")
            if post.views > 0 { stat(post.views, systemImage: "eye") }
        }
    }

    private func stat(_ value: Int, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).imageScale(.small)
            Text(value, format: .number.notation(.compactName)).monospacedDigit()
        }
        .lineLimit(1).fixedSize()
    }
}
