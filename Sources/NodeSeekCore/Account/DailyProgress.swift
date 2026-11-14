public struct DailyProgress: Decodable, Sendable {
    public let postBonusCount: Int
    public let maxPostBonusCount: Int
    public let commentBonusCount: Int
    public let maxCommentBonusCount: Int
    public let freeLikeUsed: Int
    public let maxFreeLike: Int
}
