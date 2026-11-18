#if DEBUG
import NodeSeekClient
import NodeSeekCore
import SwiftUI

/// Opens the feed post or conversation that a UI test names once the app loads, the same way a tap would.
/// UI tests on a Mac can't click into the app, so this is how they reach pushed pages there.
struct UITestPostOpener: ViewModifier {
    let posts: [PostSummary]
    let isEnabled: Bool
    @Environment(AccountSession.self) private var account
    @Environment(\.openPost) private var openPost
    @Environment(\.openMemberDestination) private var openMember
    @State private var hasOpened = false
    private static let postID = ProcessInfo.processInfo.environment["NODESEEK_UI_TEST_OPEN_POST"].flatMap(Int.init)
    private static let conversationPeer: MessageRecipient? = {
        guard let raw = ProcessInfo.processInfo.environment["NODESEEK_UI_TEST_OPEN_CONVERSATION"] else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let id = Int(parts[0]) else { return nil }
        return MessageRecipient(id: id, name: String(parts[1]))
    }()

    func body(content: Content) -> some View {
        content
            .onChange(of: posts, initial: true) {
                guard isEnabled, !hasOpened, let id = Self.postID, let post = posts.first(where: { $0.id == id }) else { return }
                hasOpened = true
                openPost(post)
            }
            .onChange(of: account.user?.id, initial: true) {
                guard isEnabled, !hasOpened, account.isLoggedIn, let peer = Self.conversationPeer else { return }
                hasOpened = true
                openMember(.conversation(peer))
            }
    }
}
#endif
