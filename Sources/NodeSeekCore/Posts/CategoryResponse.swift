public struct CategoryResponse: Decodable, Sendable {
    public let success: Bool
    public let data: [ForumCategory]
}
