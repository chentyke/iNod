import Foundation

public struct BlockedMember: Decodable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    public var avatarURL: URL {
        NodeSeekRoute.origin.appending(path: "avatar/\(id).png")
    }

    /// Trims surrounding whitespace and an optional leading `@` mention prefix.
    /// Returns `nil` when empty.
    public static func normalizedUsername(_ input: String) -> String? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? nil : trimmed
    }
}
