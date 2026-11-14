public struct ForumNotice: Decodable, Identifiable, Sendable {
    public let id: Int
    public var viewed: Bool
    public let postID: Int
    public let title: String
    public let floor: Int
    public let authorID: Int
    public let author: String
    public let createdAt: String

    public var post: AccountPost {
        AccountPost(id: "\(postID)-\(floor)", postID: postID, title: title, floor: floor, excerpt: nil, rank: nil)
    }
}
