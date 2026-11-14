import Foundation

public struct HostedImage: Decodable, Identifiable, Sendable {
    public let id: String
    public let filename: String
    public let url: URL
    public let uploadedAt: String?

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
}

public struct HostedImageList: Decodable, Sendable { public let images: [HostedImage] }
