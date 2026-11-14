public struct ReactionResponse: Decodable, Sendable {
    public let success: Bool
    public let message: String?
    public let current: Int?
    public let coin: Int?
    public let redirect: String?
    public let redirectHash: String?
}
