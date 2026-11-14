import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct MemberConversationView: View {
    let peer: MessageRecipient
    @Environment(AccountSession.self) private var account
    var body: some View {
        if let user = account.user {
            if user.id == peer.id {
                ContentUnavailableView("不能给自己发私信", systemImage: "bubble.left")
            } else {
                ConversationView(peer: peer, userID: user.id).id(user.id)
            }
        } else {
            MemberSignInView()
        }
    }
}
