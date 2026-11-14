import SwiftUI
import NodeSeekCore

enum MemberDestination: Hashable {
    case profile(Int)
    case conversation(MessageRecipient)
    case posts(AccountContentKind, userID: Int)
    case editProfile
}

struct MemberNavigationAction {
    let open: @MainActor (MemberDestination) -> Void
    @MainActor func callAsFunction(_ destination: MemberDestination) { open(destination) }
}

extension EnvironmentValues {
    @Entry var openMemberDestination = MemberNavigationAction { _ in }
}
