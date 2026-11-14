public struct PostDetail: Decodable, Sendable {
    public let postId: Int
    public let title: String
    public let categoryWord: String
    public let views: String
    public let postPage: Int
    public let postPageCount: Int
    public let collectionCount: Int
    public let category: String?
    public let rank: Int?
    @WebsiteFlag public var locked: Bool?
    @WebsiteFlag public var collected: Bool?
    @WebsiteFlag public var award: Bool?
    public let op: ForumUser
    public var comments: [ForumComment]

    public var replies: [ForumComment] {
        var seenIDs = Set<Int>()
        let pinned = comments.filter {
            $0.floorIndex > 0 && $0.pined == true && seenIDs.insert($0.id).inserted
        }
        let hot = comments.filter {
            $0.floorIndex > 0 && $0.hot == true && seenIDs.insert($0.id).inserted
        }
        let remaining = comments.filter {
            $0.floorIndex > 0 && seenIDs.insert($0.id).inserted
        }
        return pinned + hot + remaining
    }
}
