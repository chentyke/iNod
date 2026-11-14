import Foundation

public struct DirectoryEntry: Decodable, Sendable, Identifiable {
    public let title: String
    public let url: URL
    public let image: URL?
    public var id: String { url.absoluteString }
}
