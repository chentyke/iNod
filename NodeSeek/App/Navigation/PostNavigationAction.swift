import NodeSeekCore
import SwiftUI

struct PostNavigationAction {
    let open: @MainActor (PostSummary) -> Void

    @MainActor func callAsFunction(_ post: PostSummary) { open(post) }
}

extension EnvironmentValues {
    @Entry var openPost = PostNavigationAction { _ in }
    /// Namespace the navigation stack zooms posts from; nil outside a `ForumNavigationStack`.
    @Entry var postTransitionNamespace: Namespace.ID? = nil
}

extension View {
    /// Marks this view as the card a post zooms out of when it opens.
    func postTransitionSource(_ post: PostSummary) -> some View {
        modifier(PostTransitionSource(id: post.id))
    }
}

private struct PostTransitionSource: ViewModifier {
    let id: Int
    @Environment(\.postTransitionNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { $0.clipShape(.rect(cornerRadius: PostRow.cornerRadius)) }
        } else {
            content
        }
    }
}


struct AccountPostNavigationAction {
    var perform: (AccountPost) -> Void = { _ in }
    func callAsFunction(_ post: AccountPost) { perform(post) }
}

extension EnvironmentValues {
    @Entry var openAccountPost = AccountPostNavigationAction()
}
