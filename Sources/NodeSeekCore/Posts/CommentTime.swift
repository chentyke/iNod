import Foundation

public struct CommentTime: Decodable, Sendable {
    public let createdDate: String
    public let editedDate: String?
    public var date: Date? { ISO8601DateFormatter.nodeSeek.date(from: createdDate) }
}

public extension ISO8601DateFormatter {
    static var nodeSeek: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
