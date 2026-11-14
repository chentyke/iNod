public enum CommentReaction: String, Sendable {
    case upvote, like, dislike

    public var title: String {
        switch self {
        case .upvote: "点赞"
        case .like: "投喂鸡腿"
        case .dislike: "反对"
        }
    }
}
