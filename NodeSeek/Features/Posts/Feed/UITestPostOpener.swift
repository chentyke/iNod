#if DEBUG
import NodeSeekCore
import SwiftUI

/// Opens the feed post that `NODESEEK_UI_TEST_OPEN_POST` names once it loads, the same way a tap on its card would.
/// UI tests on a Mac can't click into the app, so this is how they reach a thread there.
struct UITestPostOpener: ViewModifier {
    let posts: [PostSummary]
    let isEnabled: Bool
    @Environment(\.openPost) private var openPost
    @State private var hasOpened = false
    private static let postID = ProcessInfo.processInfo.environment["NODESEEK_UI_TEST_OPEN_POST"].flatMap(Int.init)

    func body(content: Content) -> some View {
        content.onChange(of: posts, initial: true) {
            guard isEnabled, !hasOpened, let id = Self.postID, let post = posts.first(where: { $0.id == id }) else { return }
            hasOpened = true
            openPost(post)
        }
    }
}
#endif
