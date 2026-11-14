import NodeSeekCore
import Foundation
import ImageIO

@MainActor
public final class AvatarImageLoader {
    public static let shared = AvatarImageLoader()

    private final class Entry {
        let image: CGImage?
        let expiresAt: Date
        init(image: CGImage?, lifetime: TimeInterval) {
            self.image = image
            expiresAt = .now.addingTimeInterval(lifetime)
        }
    }

    private let cache = NSCache<NSURL, Entry>()
    private var pending: [URL: Task<CGImage, Error>] = [:]
    private let session: URLSession

    init(session: URLSession? = nil) {
        cache.countLimit = 256
        cache.totalCostLimit = 8_000_000
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = nil
            configuration.urlCache = URLCache(memoryCapacity: 8_000_000, diskCapacity: 64_000_000, directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "AvatarsHTTP"))
            self.session = URLSession(configuration: configuration)
        }
    }

    public func image(for url: URL) -> CGImage? { entry(for: url)?.image }

    public func load(_ url: URL) async throws -> CGImage {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw SiteError.invalidResponse }
        if let entry = entry(for: url) {
            guard let image = entry.image else { throw SiteError.message("头像暂时无法加载。") }
            return image
        }
        if let task = pending[url] { return try await task.value }
        let session = session
        let task = Task.detached(priority: .utility) {
            var request = ForumImageRequest.make(url: url)
            request.cachePolicy = .useProtocolCachePolicy
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 4_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 384,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw SiteError.message("头像暂时无法加载。") }
            return image
        }
        pending[url] = task
        defer { pending[url] = nil }
        do {
            let image = try await task.value
            cache.setObject(Entry(image: image, lifetime: 3600), forKey: url as NSURL, cost: image.bytesPerRow * image.height)
            return image
        } catch {
            cache.setObject(Entry(image: nil, lifetime: 30), forKey: url as NSURL)
            throw error
        }
    }

    private func entry(for url: URL) -> Entry? {
        guard let entry = cache.object(forKey: url as NSURL) else { return nil }
        guard entry.expiresAt > .now else { cache.removeObject(forKey: url as NSURL); return nil }
        return entry
    }
}
