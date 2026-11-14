import Foundation

public struct ForumUser: Decodable, Sendable {
    public let uid: Int
    public let name: String
    public let avatar: String?
    public var avatarURL: URL? { avatar.flatMap { URL(string: $0, relativeTo: NodeSeekRoute.origin)?.absoluteURL } ?? NodeSeekRoute.origin.appending(path: "avatar/\(uid).png") }
}
