import NodeSeekCore
import SwiftUI

struct CommentReactionConfirmation: ViewModifier {
    let commentID: Int
    let reaction: CommentReaction
    @Binding var pending: PendingReaction?
    @Binding var isPresented: Bool
    let onConfirm: (PendingReaction) -> Void

    private var matchesPending: Bool {
        pending?.commentID == commentID && pending?.reaction == reaction
    }

    private var presentation: Binding<Bool> {
        Binding {
            isPresented && matchesPending
        } set: { presented in
            guard matchesPending else { return }
            isPresented = presented
            if !presented { pending = nil }
        }
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(reaction.title, isPresented: presentation, titleVisibility: .visible, presenting: pending) { pending in
            Button(reaction.title, role: reaction == .dislike ? .destructive : nil) {
                onConfirm(pending)
            }
            Button("取消", role: .cancel) { }
        } message: { pending in
            Text(pending.message)
        }
    }
}
