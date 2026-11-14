public struct LedgerEntry: Decodable, Identifiable, Sendable {
    public let id: String
    public let change: Int
    public let balance: Int
    public let reason: String
    public let createdAt: String
    public let peerID: Int?
}
