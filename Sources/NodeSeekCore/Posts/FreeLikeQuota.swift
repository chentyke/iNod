public struct FreeLikeQuota: Decodable, Sendable {
    public let maxFreeLike: Int
    public let freeLikeUsed: Int
    public var cost: Int { maxFreeLike > freeLikeUsed ? 0 : 1 }
}
