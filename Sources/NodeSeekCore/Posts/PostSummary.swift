import Foundation

public struct PostSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let author: String
    public var authorID: Int? = nil
    public let avatar: String
    public let category: String
    public let categoryKey: String
    public let views: Int
    public let replies: Int
    public let activityDate: String
    public let pinned: Bool
    public var rank: Int? = nil

    public var url: URL { NodeSeekRoute.thread(id: id, page: 1).url }
    public var avatarURL: URL? { URL(string: avatar, relativeTo: NodeSeekRoute.origin)?.absoluteURL }
}
