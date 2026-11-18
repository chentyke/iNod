import NodeSeekCore
import Foundation
import ImageIO
import WebKit

@MainActor
public final class AvatarImageLoader {
    public static let shared = AvatarImageLoader()
    private nonisolated static let maxPixelSize = 384

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
    private lazy var svgWebView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }()

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
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  data.count <= 4_000_000 else { throw SiteError.message("头像暂时无法加载。") }

            // NodeSeek serves SVG default avatars from .png URLs.
            let imageData = response.mimeType == "image/svg+xml"
                ? try await self.rasterizeSVG(data.base64EncodedString()) : data
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  CGImageSourceGetCount(source) > 0,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize,
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

    private func rasterizeSVG(_ base64: String) async throws -> Data {
        // Loading SVG through an image element disables its scripts and external resources.
        let result = try await svgWebView.callAsyncJavaScript("""
            const image = new Image();
            image.src = "data:image/svg+xml;base64," + svg;
            await image.decode();

            const scale = Math.min(1, maxPixelSize / Math.max(image.naturalWidth, image.naturalHeight));
            const canvas = document.createElement("canvas");
            canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
            canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
            // The thumbnail is read straight back into Swift; draw in CPU memory even without a visible window.
            const context = canvas.getContext("2d", { willReadFrequently: true });
            if (!context) throw new Error("Could not create the avatar canvas");
            context.drawImage(image, 0, 0, canvas.width, canvas.height);
            const png = canvas.toDataURL("image/png").split(",")[1];
            if (!png) throw new Error("The avatar canvas returned no PNG");
            return png;
            """, arguments: ["svg": base64, "maxPixelSize": Self.maxPixelSize], in: nil, contentWorld: .defaultClient)
        guard let base64PNG = result as? String, let png = Data(base64Encoded: base64PNG) else {
            throw SiteError.message("头像暂时无法加载。")
        }
        return png
    }

    private func entry(for url: URL) -> Entry? {
        guard let entry = cache.object(forKey: url as NSURL) else { return nil }
        guard entry.expiresAt > .now else { cache.removeObject(forKey: url as NSURL); return nil }
        return entry
    }
}
