public struct MessageDraft: Codable, Equatable, Sendable {
    public var content: String
    public var isMarkdown: Bool

    public init(content: String = "", isMarkdown: Bool = false) {
        self.content = content; self.isMarkdown = isMarkdown
    }
    public static func key(ownerID: Int, peerID: Int) -> String { "message-draft-\(ownerID)-\(peerID)" }
}
