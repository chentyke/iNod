import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct ReplyView: View {
    let post: PostSummary
    let onSent: () -> Void
    @Environment(AccountSession.self) private var account
    var body: some View {
        if account.isLoggedIn {
            ForumEditorView(request: .init(mode: .reply(postID: post.id), seed: EditorDraft()),legacyDraftKey:"reply-draft-\(post.id)") { _ in
                onSent()
            }
        } else { MemberSignInView() }
    }
}
