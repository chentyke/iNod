public struct DailyProgress: Decodable, Equatable, Sendable {
    public struct Quota: Equatable, Sendable {
        public let used: Int
        public let limit: Int

        public init(used: Int, limit: Int) {
            self.used = max(0, used)
            self.limit = max(0, limit)
        }

        public var remaining: Int {
            max(0, limit - used)
        }

        public var isReached: Bool {
            limit > 0 && used >= limit
        }

        public var fraction: Double {
            guard limit > 0 else { return 0 }
            return min(max(Double(used) / Double(limit), 0), 1)
        }
    }

    public let postBonusCount: Int
    public let maxPostBonusCount: Int
    public let commentBonusCount: Int
    public let maxCommentBonusCount: Int
    public let freeLikeUsed: Int
    public let maxFreeLike: Int

    public init(
        postBonusCount: Int,
        maxPostBonusCount: Int,
        commentBonusCount: Int,
        maxCommentBonusCount: Int,
        freeLikeUsed: Int,
        maxFreeLike: Int
    ) {
        self.postBonusCount = postBonusCount
        self.maxPostBonusCount = maxPostBonusCount
        self.commentBonusCount = commentBonusCount
        self.maxCommentBonusCount = maxCommentBonusCount
        self.freeLikeUsed = freeLikeUsed
        self.maxFreeLike = maxFreeLike
    }

    public var postBonus: Quota {
        Quota(used: postBonusCount, limit: maxPostBonusCount)
    }

    public var commentBonus: Quota {
        Quota(used: commentBonusCount, limit: maxCommentBonusCount)
    }

    public var freeLike: Quota {
        Quota(used: freeLikeUsed, limit: maxFreeLike)
    }
}
