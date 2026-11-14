public struct AccountPost: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let postID: Int
    public let title: String
    public let floor: Int
    public let excerpt: String?
    public let rank: Int?

    public var page: Int { floor <= 10 ? 1 : (floor - 1) / 10 + 1 }
    public var summary: PostSummary {
        PostSummary(id: postID, title: title, author: "", avatar: "", category: "", categoryKey: "", views: 0, replies: 0, activityDate: "", pinned: false, rank: rank)
    }
}
