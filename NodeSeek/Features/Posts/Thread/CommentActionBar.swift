import NodeSeekCore
import SwiftUI

/// The footer of a reply: its time on the left and a folded reaction dock on the right.
/// The dock shows three colored dots until tapped, then opens into the full actions.
struct CommentActionBar: View {
    let comment: ForumComment
    var date: Date?
    let isBusy: Bool
    let actionsDisabled: Bool
    let canEdit: Bool
    let canPin: Bool
    @Binding var isExpanded: Bool
    @Binding var pendingReaction: PendingReaction?
    @Binding var showsReactionConfirmation: Bool
    let onReply: (Bool) -> Void
    let onEdit: () -> Void
    let onPin: () -> Void
    let onConfirmReaction: (PendingReaction) -> Void
    let onReact: (CommentReaction) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The distance from the row's trailing edge to the card's edge. The dock shifts toward the card's edge
    /// by part of it, so its side gap always matches its bottom gap, folded or open.
    var trailingInset: CGFloat = 0
    @State private var confirmsPin = false
    @State private var revealsItems = false

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Large text has no room for an opening dock, so every action lives in one menu.
                VStack(alignment: .leading, spacing: 4) {
                    timestamp
                    Menu { reactionMenuItems; replyMenuItems } label: { foldedDock }
                        .buttonStyle(.seekRow)
                        .modifier(CommentReactionConfirmation(commentID: comment.id, reaction: .like,
                                                              pending: $pendingReaction, isPresented: $showsReactionConfirmation,
                                                              onConfirm: onConfirmReaction))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    timestamp
                    Spacer(minLength: 0)
                }
                .frame(height: DockMetrics.foldedHeight)
                // Overlaid on the row so opening the dock never changes the card's height. Folded, it sits
                // `cardInset` from the side and bottom; open, it keeps `openMargin` from the side, the
                // bottom and the text above.
                .overlay(alignment: .trailing) {
                    dock.offset(x: trailingInset - (isExpanded ? DockMetrics.openMargin : DockMetrics.cardInset),
                                y: isExpanded ? DockMetrics.openDrop : 0)
                        .modifier(CommentReactionConfirmation(commentID: comment.id, reaction: .like,
                                                              pending: $pendingReaction, isPresented: $showsReactionConfirmation,
                                                              onConfirm: onConfirmReaction))
                }
            }
        }
        .modifier(CommentReactionConfirmation(commentID: comment.id, reaction: .dislike,
                                              pending: $pendingReaction, isPresented: $showsReactionConfirmation,
                                              onConfirm: onConfirmReaction))
        .background {
            Color.clear.confirmationDialog("置顶这条回复？", isPresented: $confirmsPin, titleVisibility: .visible) {
                Button("消耗 5 个鸡腿并置顶", action: onPin)
                Button("取消", role: .cancel) { }
            } message: { Text("置顶回复需要 5 个鸡腿，取消置顶免费。") }
        }
    }

    @ViewBuilder private var timestamp: some View {
        if let date {
            PostTimestamp(date: date)
                .font(.caption).foregroundStyle(.tertiary)
                .monospacedDigit().lineLimit(1)
        }
    }

    private var dock: some View {
        ZStack(alignment: .trailing) {
            if isExpanded {
                openDock
                    // While it fades out, a quick tap on the folding dock must not land on a vanishing action.
                    .allowsHitTesting(isExpanded)
                    // The items reveal themselves; the dock only needs a quick fade on the way out.
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .opacity.animation(.easeOut(duration: 0.12))))
                    .onAppear { revealsItems = true }
                    .onDisappear { revealsItems = false }
            } else {
                Button { setExpanded(true) } label: { foldedDock }
                    .buttonStyle(.seekRow)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.1)),
                                            removal: .opacity.animation(.easeOut(duration: 0.1))))
                    .accessibilityLabel(isBusy ? "正在提交" : "回复操作，\(reactionSummary)")
                    .accessibilityHint("展开点赞、鸡腿、反对和回复")
                    .accessibilityActions { reactionMenuItems; replyMenuItems }
            }
        }
        // Clip to the glass so every change happens inside it while the capsule grows from its trailing edge.
        .clipShape(.capsule)
        .glassEffect(.regular, in: .capsule)
        // The folded dock is small; let taps just around it open it too.
        .contentShape(Rectangle().inset(by: -9))
        .gesture(TapGesture().onEnded { setExpanded(true) }, including: isExpanded ? .subviews : .all)
    }

    private var foldedDock: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView().controlSize(.mini)
            } else {
                CommentReactionDot(tint: .seekGreen, count: comment.upvoteCount, isSelected: comment.upvoted == true)
                CommentReactionDot(tint: .orange, count: comment.likeCount, isSelected: comment.liked == true)
                CommentReactionDot(tint: .red, count: comment.dislikeCount, isSelected: comment.disliked == true)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: DockMetrics.foldedHeight)
    }

    private var openDock: some View {
        // Items reveal from the trailing edge, where the folded dots were, toward the leading edge.
        HStack(spacing: 0) {
            reactionButton(.upvote, symbol: comment.upvoted == true ? "hand.thumbsup.fill" : "hand.thumbsup",
                           count: comment.upvoteCount, tint: .seekGreen, isSelected: comment.upvoted == true)
                .accessibilityLabel("\(comment.upvoteCount) 个赞，\(comment.upvoted == true ? "已点赞" : "点赞")")
                .modifier(DockItemReveal(isShown: revealsItems, order: 4))
            reactionButton(.like, symbol: "fork.knife", count: comment.likeCount, tint: .orange, isSelected: comment.liked == true)
                .accessibilityLabel("\(comment.likeCount) 个鸡腿，\(comment.liked == true ? "已投喂" : "投喂鸡腿")")
                .modifier(DockItemReveal(isShown: revealsItems, order: 3))
            reactionButton(.dislike, symbol: comment.disliked == true ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                           count: comment.dislikeCount, tint: .red, isSelected: comment.disliked == true)
                .accessibilityLabel(comment.dislikeCount.map { "反对，\($0) 次" } ?? "反对")
                .modifier(DockItemReveal(isShown: revealsItems, order: 2))
            Divider().frame(height: 14).padding(.horizontal, 2)
                .modifier(DockItemReveal(isShown: revealsItems, order: 2))
            Button { setExpanded(false); onReply(false) } label: { CommentToolButtonLabel(symbol: "arrowshape.turn.up.left") }
                .accessibilityLabel("回复")
                .modifier(DockItemReveal(isShown: revealsItems, order: 1))
            Menu { replyMenuItems } label: { CommentToolButtonLabel(symbol: "ellipsis") }
                .accessibilityLabel("更多回复操作")
                .modifier(DockItemReveal(isShown: revealsItems, order: 0))
        }
        .buttonStyle(.seekRow)
        .frame(height: DockMetrics.openHeight)
    }

    private func reactionButton(_ reaction: CommentReaction, symbol: String, count: Int?, tint: Color, isSelected: Bool) -> some View {
        Button {
            setExpanded(false)
            onReact(reaction)
        } label: {
            CommentReactionPill(symbol: symbol, count: count, tint: tint, isSelected: isSelected)
        }
        .disabled(actionsDisabled || isSelected)
    }

    @ViewBuilder private var reactionMenuItems: some View {
        Button(comment.upvoted == true ? "已点赞 · \(comment.upvoteCount)" : "点赞 · \(comment.upvoteCount)",
               systemImage: "hand.thumbsup") { onReact(.upvote) }
            .disabled(actionsDisabled || comment.upvoted == true)
        Button(comment.liked == true ? "已投喂 · \(comment.likeCount)" : "投喂鸡腿 · \(comment.likeCount)",
               systemImage: "fork.knife") { onReact(.like) }
            .disabled(actionsDisabled || comment.liked == true)
        Button(comment.disliked == true ? "已反对" : "反对", systemImage: "hand.thumbsdown") { onReact(.dislike) }
            .disabled(actionsDisabled || comment.disliked == true)
    }

    @ViewBuilder private var replyMenuItems: some View {
        Button("回复", systemImage: "arrowshape.turn.up.left") { setExpanded(false); onReply(false) }
        Button("引用回复", systemImage: "quote.opening") { setExpanded(false); onReply(true) }
        if canEdit { Button("编辑", systemImage: "pencil") { setExpanded(false); onEdit() } }
        if canPin {
            Button(comment.pined == true ? "取消置顶" : "置顶回复", systemImage: "pin") {
                setExpanded(false)
                if comment.pined == true { onPin() }
                else { confirmsPin = true }
            }
        }
    }

    private var reactionSummary: String {
        var parts = ["\(comment.upvoteCount) 个赞", "\(comment.likeCount) 个鸡腿"]
        if let dislikes = comment.dislikeCount { parts.append("\(dislikes) 次反对") }
        return parts.joined(separator: "，")
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.38, bounce: 0.18)) { isExpanded = expanded }
    }
}

/// Fades and gently grows one opened-dock item into place, a beat after the item to its right.
private struct DockItemReveal: ViewModifier {
    let isShown: Bool
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.6)
            .blur(radius: isShown || reduceMotion ? 0 : 3)
            .animation(reduceMotion ? .easeOut(duration: 0.15)
                                    : .spring(duration: 0.34, bounce: 0.28).delay(0.05 + Double(order) * 0.03),
                       value: isShown)
    }
}
