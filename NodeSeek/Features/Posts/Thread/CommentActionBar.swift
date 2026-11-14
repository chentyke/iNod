import NodeSeekCore
import SwiftUI

struct CommentActionBar: View {
    let comment: ForumComment
    let isBusy: Bool
    let actionsDisabled: Bool
    let canEdit: Bool
    let canPin: Bool
    @Binding var pendingReaction: PendingReaction?
    @Binding var showsReactionConfirmation: Bool
    let onReply: (Bool) -> Void
    let onEdit: () -> Void
    let onPin: () -> Void
    let onConfirmReaction: (PendingReaction) -> Void
    let onReact: (CommentReaction) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmsPin = false

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 0))
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24)
        layout {
            Button { onReact(.upvote) } label: {
                Label(comment.upvoteCount.formatted(), systemImage: comment.upvoted == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .labelStyle(.titleAndIcon)
                    .modifier(CommentActionSegment(tint: .seekGreen, isSelected: comment.upvoted == true))
            }
            .disabled(actionsDisabled || comment.upvoted == true)
            .accessibilityLabel("\(comment.upvoteCount) 个赞，\(comment.upvoted == true ? "已点赞" : "点赞")")
            Divider().overlay(Color.seekHairline.opacity(0.6))
            Button { onReact(.like) } label: {
                Label(comment.likeCount.formatted(), systemImage: comment.liked == true ? "checkmark" : "fork.knife")
                    .labelStyle(.titleAndIcon)
                    .modifier(CommentActionSegment(tint: .orange, isSelected: comment.liked == true))
            }
            .disabled(actionsDisabled || comment.liked == true)
            .accessibilityLabel("\(comment.likeCount) 个鸡腿，\(comment.liked == true ? "已投喂" : "投喂鸡腿")")
            .modifier(CommentReactionConfirmation(commentID: comment.id, reaction: .like,
                                                  pending: $pendingReaction, isPresented: $showsReactionConfirmation,
                                                  onConfirm: onConfirmReaction))
            Divider().overlay(Color.seekHairline.opacity(0.6))
            Button { onReact(.dislike) } label: {
                Label(comment.dislikeCount.map { $0.formatted() } ?? "—", systemImage: comment.disliked == true ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .labelStyle(.titleAndIcon)
                    .modifier(CommentActionSegment(tint: .red, isSelected: comment.disliked == true))
            }
            .disabled(actionsDisabled || comment.disliked == true)
            .accessibilityLabel(comment.dislikeCount.map { "反对，\($0) 次" } ?? "反对")
            .modifier(CommentReactionConfirmation(commentID: comment.id, reaction: .dislike,
                                                  pending: $pendingReaction, isPresented: $showsReactionConfirmation,
                                                  onConfirm: onConfirmReaction))
            Divider().overlay(Color.seekHairline.opacity(0.6))
            Menu {
                Button("回复", systemImage: "arrowshape.turn.up.left") { onReply(false) }
                Button("引用回复", systemImage: "quote.opening") { onReply(true) }
                if canEdit { Button("编辑", systemImage: "pencil", action: onEdit) }
                if canPin {
                    Button(comment.pined == true ? "取消置顶" : "置顶回复", systemImage: "pin") {
                        if comment.pined == true { onPin() }
                        else { confirmsPin = true }
                    }
                }
            } label: {
                Group {
                    if isBusy { ProgressView().controlSize(.small) }
                    else { Label("回复操作", systemImage: "ellipsis").labelStyle(.iconOnly) }
                }
                .modifier(CommentActionSegment(tint: .secondary))
            }
            .accessibilityLabel(isBusy ? "正在提交" : "回复操作")
            .confirmationDialog("置顶这条回复？", isPresented: $confirmsPin, titleVisibility: .visible) {
                Button("消耗 5 个鸡腿并置顶", action: onPin)
                Button("取消", role: .cancel) { }
            } message: { Text("置顶回复需要 5 个鸡腿，取消置顶免费。") }
        }
        .buttonStyle(.seekRow).font(.footnote.weight(.semibold)).monospacedDigit()
        .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
        .background(Color.seekCard)
        .clipShape(shape)
        .overlay(alignment: .top) { Rectangle().fill(Color.seekHairline.opacity(0.6)).frame(height: 0.5).allowsHitTesting(false) }
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [Color.seekGreen.opacity(0.35), .orange.opacity(0.35), .red.opacity(0.35), Color.seekHairline],
                                              startPoint: .leading, endPoint: .trailing), lineWidth: 0.75)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
    }
}
