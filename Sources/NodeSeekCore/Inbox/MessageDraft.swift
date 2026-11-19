public struct MessageDraft: Codable, Equatable, Sendable {
    public var content: String

    public init(content: String = "") {
        self.content = content
    }
    public static func key(ownerID: Int, peerID: Int) -> String { "message-draft-\(ownerID)-\(peerID)" }
}
