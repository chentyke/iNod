public struct LoginRecord: Decodable, Identifiable, Sendable {
    public let id: String
    public let ip: String
    public let createdAt: String
}
