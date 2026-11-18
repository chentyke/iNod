import Foundation

public struct HostedImage: Decodable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let filename: String
    public let url: URL
    public let uploadedAt: String?

    public init(id: String, filename: String, url: URL, uploadedAt: String? = nil) {
        self.id = id
        self.filename = filename
        self.url = url
        self.uploadedAt = uploadedAt
    }

    private enum CodingKeys: String, CodingKey { case image_id, imageId, filename, links, url, upload_time, uploadTime }
    private struct Links: Decodable { let direct: String? }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .image_id) ?? values.decodeIfPresent(String.self, forKey: .imageId) ?? ""
        let address = try values.decodeIfPresent(Links.self, forKey: .links)?.direct ?? values.decodeIfPresent(String.self, forKey: .url)
        guard let address, let parsed = URL(string: address), parsed.scheme == "https", parsed.host() != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing HTTPS image URL"))
        }
        url = parsed
        filename = try values.decodeIfPresent(String.self, forKey: .filename) ?? parsed.lastPathComponent
        uploadedAt = try values.decodeIfPresent(String.self, forKey: .upload_time) ?? values.decodeIfPresent(String.self, forKey: .uploadTime)
    }

    public var formatBadge: String? {
        let candidate = (filename as NSString).pathExtension.isEmpty
            ? url.pathExtension
            : (filename as NSString).pathExtension
        let lower = candidate.lowercased()
        guard (2...5).contains(lower.count),
              lower.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }
        return lower == "jpeg" ? "JPG" : lower.uppercased()
    }
}

public struct HostedImageList: Decodable, Sendable { public let images: [HostedImage] }
