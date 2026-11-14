public struct FeedPage: Decodable, Sendable {
    public let posts: [PostSummary]
    public let pinnedPosts: [PostSummary]
    public let hasNextPage: Bool

    private enum CodingKeys: String, CodingKey { case posts, pinnedPosts, hasNextPage }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let listPosts = try container.decode([PostSummary].self, forKey: .posts)
        let carouselPosts = try container.decodeIfPresent([PostSummary].self, forKey: .pinnedPosts) ?? []
        var pinnedIDs = Set<Int>()
        pinnedPosts = (carouselPosts + listPosts.filter(\.pinned)).filter { pinnedIDs.insert($0.id).inserted }
        posts = listPosts.filter { !pinnedIDs.contains($0.id) }
        hasNextPage = try container.decode(Bool.self, forKey: .hasNextPage)
    }
}
