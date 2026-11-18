public struct HomepageCategory: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public var enabled: Bool

    public init(id: String, title: String, enabled: Bool) {
        self.id = id
        self.title = title
        self.enabled = enabled
    }

    public var symbol: String {
        ForumCategory.all.first { $0.id == id }?.symbol ?? "bubble.left.and.bubble.right"
    }
}
