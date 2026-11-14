public struct DirectMessage: Decodable, Identifiable, Sendable {
    public let id: Int
    public let senderID: Int
    public let receiverID: Int
    public let content: String
    public let createdAt: String
    public let isMarkdown: Bool
    public var viewed: Bool
}
