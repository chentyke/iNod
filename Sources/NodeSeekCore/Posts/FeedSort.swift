public enum FeedSort: String, CaseIterable, Identifiable, Sendable {
    case replyTime
    case postTime

    public var id: String { rawValue }
    public var title: String { self == .replyTime ? "新评论" : "新帖子" }
}
