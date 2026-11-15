import CryptoKit
import Foundation
import NodeSeekCore

@MainActor
public final class NodeImageHistory {
    public private(set) lazy var client = NodeImageClient()
    private struct Entry {
        let userID: Int
        let credential: SHA256.Digest
        let images: [HostedImage]
    }
    private var entry: Entry?

    public func cachedImages(userID: Int, key: String) -> [HostedImage]? {
        guard let entry, entry.userID == userID,
              entry.credential == SHA256.hash(data: Data(key.utf8)) else { return nil }
        return entry.images
    }

    public func store(_ images: [HostedImage], userID: Int, key: String) {
        entry = Entry(userID: userID, credential: SHA256.hash(data: Data(key.utf8)), images: images)
    }

    public func recordUpload(_ image: HostedImage, userID: Int, key: String) {
        guard !image.id.isEmpty, var images = cachedImages(userID: userID, key: key) else { return }
        images.removeAll { $0.id == image.id }
        images.insert(image, at: 0)
        store(images, userID: userID, key: key)
    }

    public func finishRefresh(_ images: [HostedImage], recentUploads: [HostedImage], userID: Int, key: String) -> [HostedImage] {
        let uploadedIDs = Set(recentUploads.map(\.id))
        let merged = Array(recentUploads.reversed()) + images.filter { !uploadedIDs.contains($0.id) }
        store(merged, userID: userID, key: key)
        return merged
    }

    public func reset() { entry = nil }
}
