import NodeSeekCore
import Foundation
import ImageIO

public actor ForumImageLoader {
    public static let shared = ForumImageLoader()
    private static let byteLimit = 24_000_000

    public enum Size: Hashable, Sendable {
        case full
        case thumbnail

        fileprivate var maxPixels: Int {
            // The 76-point NodeImage row needs at most 228 pixels at 3× scale.
            self == .thumbnail ? 240 : 1600
        }
    }

    private struct Key: Hashable {
        let url: URL
        let size: Size
    }

    private struct Download {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<CGImage, Error>]
    }

    private let session: URLSession
    private var cache: [Key: CGImage] = [:]
    private var recent: [Key] = []
    private var cachedBytes = 0
    private var pending: [Key: Download] = [:]

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 8_000_000, diskCapacity: 64_000_000,
                directory: URL.cachesDirectory.appending(path: "ForumImagesHTTP", directoryHint: .isDirectory))
            self.session = URLSession(configuration: configuration)
        }
    }

    public func load(_ url: URL, size: Size = .full, prioritized: Bool = false) async throws -> CGImage {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw SiteError.invalidResponse }
        try Task.checkCancellation()
        let key = Key(url: url, size: size)
        if let image = cache[key] {
            recent.removeAll { $0 == key }
            recent.append(key)
            return image
        }

        let waiterID = UUID()
        let image: CGImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if pending[key] != nil {
                    pending[key]?.waiters[waiterID] = continuation
                } else {
                    let id = UUID()
                    let task = Task(priority: prioritized ? .userInitiated : .utility) {
                        let result: Result<CGImage, Error>
                        do { result = .success(try await download(key, prioritized: prioritized)) }
                        catch { result = .failure(error) }
                        finish(key, id: id, result: result)
                    }
                    pending[key] = Download(id: id, task: task, waiters: [waiterID: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancel(key, waiterID: waiterID) }
        }
        try Task.checkCancellation()
        return image
    }

    private func cancel(_ key: Key, waiterID: UUID) {
        guard let waiter = pending[key]?.waiters.removeValue(forKey: waiterID) else { return }
        if pending[key]?.waiters.isEmpty == true {
            pending.removeValue(forKey: key)?.task.cancel()
        }
        waiter.resume(throwing: CancellationError())
    }

    private func finish(_ key: Key, id: UUID, result: Result<CGImage, Error>) {
        guard pending[key]?.id == id, let download = pending.removeValue(forKey: key) else { return }
        if case .success(let image) = result {
            let cost = image.bytesPerRow * image.height
            if cost <= Self.byteLimit {
                while recent.count >= 12 || cachedBytes + cost > Self.byteLimit {
                    if let removed = cache.removeValue(forKey: recent.removeFirst()) {
                        cachedBytes -= removed.bytesPerRow * removed.height
                    }
                }
                cache[key] = image
                recent.append(key)
                cachedBytes += cost
            }
        }
        for waiter in download.waiters.values { waiter.resume(with: result) }
    }

    private func download(_ key: Key, prioritized: Bool) async throws -> CGImage {
        try await ImageWorkLimiter.load(prioritized: prioritized) { [session] in
            var request = ForumImageRequest.make(url: key.url)
            request.cachePolicy = .useProtocolCachePolicy
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 20_000_000 else {
                throw SiteError.message("图片暂时无法加载，请重试。")
            }
            return data
        } decode: { data in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: key.size.maxPixels,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw SiteError.message("图片暂时无法加载，请重试。") }
            return image
        }
    }
}
