public struct AccountProfile: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let bio: String?
    public let readme: String?
    public let signature: String?
    public let createdAt: String?
    public let coins: Int?
    public let stardust: Int?
    public let topics: Int?
    public let replies: Int?
    public let follows: Int?
    public let fans: Int?
    public let followed: Bool?
    public var level: Int? { AccountLevel.from(coins: coins) }
    public var recipient: MessageRecipient { .init(id: id, name: name) }
}
