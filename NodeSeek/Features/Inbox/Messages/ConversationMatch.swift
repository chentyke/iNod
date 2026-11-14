import NodeSeekCore

enum ConversationMatch: Identifiable {
    case thread(MessageThread)
    case member(MessageRecipient)

    var recipient: MessageRecipient {
        switch self {
        case .thread(let thread): thread.recipient
        case .member(let member): member
        }
    }

    var id: Int { recipient.id }
}
