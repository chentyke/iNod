public struct ForumComment: Decodable, Identifiable, Sendable {
    public let commentId: Int
    public let floorIndex: Int
    public let poster: ForumUser
    public let time: CommentTime
    public let markdown: String
    public var likeCount: Int
    public var upvoteCount: Int
    public var dislikeCount: Int?
    public var liked: Bool?
    public var upvoted: Bool?
    public var disliked: Bool?
    @WebsiteFlag public var pined: Bool?
    @WebsiteFlag public var hot: Bool?
    public let signature: String?
    public let blocked: Bool
    public var id: Int { commentId }

    public func hasReacted(_ reaction: CommentReaction) -> Bool {
        switch reaction {
        case .upvote: upvoted == true
        case .like: liked == true
        case .dislike: disliked == true
        }
    }

    public mutating func apply(_ reaction: CommentReaction, count: Int) {
        switch reaction {
        case .upvote: upvoteCount = count; upvoted = true
        case .like: likeCount = count; liked = true
        case .dislike: dislikeCount = count; disliked = true
        }
    }
}
