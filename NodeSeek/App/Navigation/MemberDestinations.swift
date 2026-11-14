import NodeSeekClient
import SwiftUI

struct MemberDestinations: ViewModifier {
    @Environment(AccountSession.self) private var account
    func body(content: Content) -> some View {
        content.navigationDestination(for: MemberDestination.self) { destination in
            switch destination {
            case .profile(let id): ProfileView(userID: id)
            case .posts(let kind, let id): AccountPostsView(kind: kind, userID: id)
            case .conversation(let peer):
                MemberConversationView(peer: peer)
            case .editProfile:
                if let user = account.user { ProfileEditorView(userID: user.id).id(user.id) }
                else { MemberSignInView() }
            }
        }
    }
}

extension View {
    func memberDestinations() -> some View { modifier(MemberDestinations()) }
}
