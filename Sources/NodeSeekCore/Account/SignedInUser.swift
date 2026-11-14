import Foundation

public struct SignedInUser: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public var coins: Int?
    public let stardust: Int?
    public let topicCount: Int?
    public let commentCount: Int?
    public let collectionCount: Int?
    public var unreadCount: Int?
    public let forumRank: Int?
    public let canCustomizeStyle: Bool?

    public var level: Int? { AccountLevel.from(coins: coins) }

    public var avatarURL: URL { NodeSeekRoute.origin.appending(path: "avatar/\(id).png") }
    public func spaceURL(section: String? = nil) -> URL {
        var parts = URLComponents(url: NodeSeekRoute.origin.appending(path: "space/\(id)"), resolvingAgainstBaseURL: false)!
        parts.fragment = section
        return parts.url!
    }
}
