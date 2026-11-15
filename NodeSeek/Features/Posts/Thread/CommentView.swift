import NodeSeekCore
import SwiftUI

struct CommentView: View {
    let comment: ForumComment
    var showsHeader = true
    var isBusy = false
    var actionsDisabled = false
    var canEdit = false
    var canPin = false
    @Binding var pendingReaction: PendingReaction?
    @Binding var showsReactionConfirmation: Bool
    var onReply: (Bool) -> Void = { _ in }
    var onEdit: () -> Void = { }
    var onPin: () -> Void = { }
    let onOpenImages: (ImageGallery) -> Void
    let onConfirmReaction: (PendingReaction) -> Void
    let onReact: (CommentReaction) -> Void

    private var highlightTint: Color {
        guard showsHeader else { return .clear }
        if comment.pined == true { return .seekGreen }
        return comment.hot == true ? .red : .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                if showsHeader { HStack(spacing: 10) {
                    NavigationLink(value: MemberDestination.profile(comment.poster.uid)) {
                        HStack(spacing: 10) {
                            AvatarView(name: comment.poster.name, url: comment.poster.avatarURL)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(comment.poster.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                if let date = comment.time.date {
                                    PostTimestamp(date: date)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(minHeight: 44).contentShape(.rect)
                    }.buttonStyle(.plain).accessibilityLabel("查看 \(comment.poster.name) 的主页")
                    Spacer()
                } }
                if comment.blocked { Label("来自已屏蔽的用户",systemImage:"eye").font(.caption).foregroundStyle(.secondary) }
                // Measure the opening post as one card so image updates don't shift its beginning.
                ForumMarkdown(markdown: comment.markdown, loadsBlocksOnScroll: showsHeader, onOpenImages: onOpenImages)
                    .environment(\.defersForumImagesUntilVisible, !showsHeader)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            .background(highlightTint.opacity(0.06), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            CommentActionBar(comment: comment, isBusy: isBusy, actionsDisabled: actionsDisabled,
                             canEdit: canEdit, canPin: canPin, pendingReaction: $pendingReaction,
                             showsReactionConfirmation: $showsReactionConfirmation, onReply: onReply,
                             onEdit: onEdit, onPin: onPin, onConfirmReaction: onConfirmReaction, onReact: onReact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if showsHeader {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.seekCard)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsHeader {
                CommentFloorMark(floor: comment.floorIndex, isPinned: comment.pined == true, isHot: comment.hot == true)
                    .offset(x: 4, y: -18)
            }
        }
    }
}
