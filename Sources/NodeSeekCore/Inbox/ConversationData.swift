public struct ConversationData: Decodable, Sendable {
    public let peer: MessageRecipient
    public var items: [DirectMessage]

    public func belongs(to ownerID: Int, peerID: Int) -> Bool {
        ownerID > 0 && peerID > 0 && ownerID != peerID && peer.id == peerID && items.allSatisfy {
            ($0.senderID == ownerID && $0.receiverID == peerID) || ($0.senderID == peerID && $0.receiverID == ownerID)
        }
    }
}
