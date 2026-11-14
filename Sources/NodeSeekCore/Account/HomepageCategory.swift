public struct HomepageCategory: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public var enabled: Bool
}
