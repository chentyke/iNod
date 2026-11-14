import Foundation

public struct VoteResponse: Decodable, Sendable { public let success: Bool; public let vote: ForumVote }
public struct ForumVote: Decodable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let uid: Int
    @WebsiteBool public var isPublic: Bool
    @WebsiteBool public var locked: Bool
    @WebsiteBool public var multiple: Bool
    public let items: [VoteItem]
    public var hasVoted: Bool { items.contains { $0.voted == true } }
    public var total: Int? {
        guard items.allSatisfy({ $0.count != nil }) else { return nil }
        return items.reduce(0) { $0 + ($1.count ?? 0) }
    }
}
public struct VoteItem: Decodable, Sendable, Identifiable {
    public let vote_item_id: Int
    public let text: String
    public let count: Int?
    @WebsiteFlag public var voted: Bool?
    public let voters: [Int]?
    public var id: Int { vote_item_id }
}
public struct VotersResponse: Decodable, Sendable { public let success: Bool; public let voters: [Int] }
