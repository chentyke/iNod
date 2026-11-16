import NodeSeekCore
import SwiftUI

struct CommentView: View {
    let comment: ForumComment
    var showsHeader = true
    var isAuthor = false
    var isBusy = false
    var actionsDisabled = false
    var canEdit = false
    var canPin = false
    /// Owned by the thread, so a scroll or a tap anywhere else can fold it.
    @Binding var actionsExpanded: Bool
    @Binding var pendingReaction: PendingReaction?
    @Binding var showsReactionConfirmation: Bool
    var onReply: (Bool) -> Void = { _ in }
    var onEdit: () -> Void = { }
    var onPin: () -> Void = { }
    let onOpenImages: (ImageGallery) -> Void
    let onConfirmReaction: (PendingReaction) -> Void
    let onReact: (CommentReaction) -> Void

    private static let radius: CGFloat = 20
    private var horizontalPadding: CGFloat { showsHeader ? 16 : 20 }

    /// The pinned reply gets a quiet outline; hot replies arrive in runs, so their badge is enough.
    private var highlightTint: Color? {
        showsHeader && comment.pined == true ? .seekGreen : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader { header }
            if comment.blocked {
                Label("来自已屏蔽的用户", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary)
            }
            // Measure the opening post as one card so image updates don't shift its beginning.
            ForumMarkdown(markdown: comment.markdown, loadsBlocksOnScroll: showsHeader, onOpenImages: onOpenImages)
                .environment(\.defersForumImagesUntilVisible, !showsHeader)
            CommentActionBar(comment: comment, date: showsHeader ? comment.time.date : nil,
                             isBusy: isBusy, actionsDisabled: actionsDisabled,
                             canEdit: canEdit, canPin: canPin, isExpanded: $actionsExpanded,
                             pendingReaction: $pendingReaction, showsReactionConfirmation: $showsReactionConfirmation,
                             onReply: onReply, onEdit: onEdit, onPin: onPin,
                             onConfirmReaction: onConfirmReaction, onReact: onReact,
                             trailingInset: horizontalPadding)
                .padding(.top, DockMetrics.bodyGap - 8)
                // The opened dock floats over the text above it.
                .zIndex(1)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, showsHeader ? 15 : 20)
        .padding(.bottom, DockMetrics.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if showsHeader {
                let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                shape.fill(Color.seekCard)
                    .overlay { if let highlightTint { shape.fill(highlightTint.opacity(0.04)) } }
            }
        }
        .overlay {
            if let highlightTint {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(highlightTint.opacity(0.28), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        // Lets the design tests measure the card's edges; VoiceOver still reads each part on its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comment-\(comment.floorIndex)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            NavigationLink(value: MemberDestination.profile(comment.poster.uid)) {
                HStack(spacing: 8) {
                    AvatarView(name: comment.poster.name, url: comment.poster.avatarURL, size: 26)
                    Text(comment.poster.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.seekInk)
                        .lineLimit(1)
                    if isAuthor { CommentBadge(title: "楼主", tint: .seekGreen) }
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle().inset(by: -7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAuthor ? "查看楼主 \(comment.poster.name) 的主页" : "查看 \(comment.poster.name) 的主页")
            CommentFloorMark(floor: comment.floorIndex, isPinned: comment.pined == true, isHot: comment.hot == true)
            Spacer(minLength: 0)
        }
    }
}
