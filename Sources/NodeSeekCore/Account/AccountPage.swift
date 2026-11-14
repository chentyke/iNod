public struct AccountPage<Item: Decodable & Sendable>: Decodable, Sendable {
    public var items: [Item]
    public let hasNext: Bool
    public let cursor: Int?

    public init(items: [Item], hasNext: Bool, cursor: Int? = nil) {
        self.items = items
        self.hasNext = hasNext
        self.cursor = cursor
    }
}
