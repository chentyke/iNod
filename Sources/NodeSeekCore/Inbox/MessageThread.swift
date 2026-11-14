public struct MessageThread: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let latestMessageID: Int?
    public let name: String
    public let preview: String
    public let isMarkdown: Bool?
    public let createdAt: String
    public var viewed: Bool
    public var recipient: MessageRecipient { .init(id: id, name: name) }
}
