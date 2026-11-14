import Foundation

public struct MessageRecipient: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) { self.id = id; self.name = name }
    public var avatarURL: URL { NodeSeekRoute.origin.appending(path: "avatar/\(id).png") }
    public var profileURL: URL { NodeSeekRoute.origin.appending(path: "space/\(id)") }
}
