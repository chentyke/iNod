import NodeSeekCore
import Foundation
import ImageIO

public actor ForumImageLoader {
    public static let shared = ForumImageLoader()
    private static let byteLimit = 24_000_000

    private struct Download {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<CGImage, Error>]
    }

    private let session: URLSession
    private var cache: [URL: CGImage] = [:]
    private var recent: [URL] = []
    private var cachedBytes = 0
    private var pending: [URL: Download] = [:]

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 8_000_000, diskCapacity: 64_000_000,
                directory: URL.cachesDirectory.appending(path: "ForumImagesHTTP", directoryHint: .isDirectory))
            self.session = URLSession(configuration: configuration)
        }
    }

    public func load(_ url: URL) async throws -> CGImage {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw SiteError.invalidResponse }
        try Task.checkCancellation()
        if let image = cache[url] {
            recent.removeAll { $0 == url }
            recent.append(url)
            return image
        }

        let waiterID = UUID()
        let image: CGImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if pending[url] != nil {
                    pending[url]?.waiters[waiterID] = continuation
                } else {
                    let id = UUID()
                    let task = Task {
                        let result: Result<CGImage, Error>
                        do { result = .success(try await download(url)) }
                        catch { result = .failure(error) }
                        finish(url, id: id, result: result)
                    }
                    pending[url] = Download(id: id, task: task, waiters: [waiterID: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancel(url, waiterID: waiterID) }
        }
        try Task.checkCancellation()
        return image
    }

    private func cancel(_ url: URL, waiterID: UUID) {
        guard let waiter = pending[url]?.waiters.removeValue(forKey: waiterID) else { return }
        if pending[url]?.waiters.isEmpty == true {
            pending.removeValue(forKey: url)?.task.cancel()
        }
        waiter.resume(throwing: CancellationError())
    }

    private func finish(_ url: URL, id: UUID, result: Result<CGImage, Error>) {
        guard pending[url]?.id == id, let download = pending.removeValue(forKey: url) else { return }
        if case .success(let image) = result {
            let cost = image.bytesPerRow * image.height
            if cost <= Self.byteLimit {
                while recent.count >= 12 || cachedBytes + cost > Self.byteLimit {
                    if let removed = cache.removeValue(forKey: recent.removeFirst()) {
                        cachedBytes -= removed.bytesPerRow * removed.height
                    }
                }
                cache[url] = image
                recent.append(url)
                cachedBytes += cost
            }
        }
        for waiter in download.waiters.values { waiter.resume(with: result) }
    }

    private func download(_ url: URL) async throws -> CGImage {
        try await ImageWorkLimiter.shared.acquire()
        defer { Task { await ImageWorkLimiter.shared.release() } }
        try Task.checkCancellation()
        var request = ForumImageRequest.make(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw SiteError.message("图片暂时无法加载，请重试。") }
        return image
    }
}
