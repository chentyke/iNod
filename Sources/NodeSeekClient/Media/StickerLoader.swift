import NodeSeekCore
import Foundation
import ImageIO
import AVFoundation

public actor StickerLoader {
    public static let shared = StickerLoader()
    private var cache: [String: StickerAnimation] = [:]
    private var pending: [String: Task<StickerAnimation?, Never>] = [:]

    #if DEBUG
    private static let fixtureResponses = ProcessInfo.processInfo.environment["NODESEEK_UI_TEST_WEBSITE"].flatMap {
        try? JSONDecoder().decode(AccountSession.UITestWebsite.self, from: Data($0.utf8)).responses
    }
    #endif

    public func load(_ sticker: ForumSticker) async -> StickerAnimation? {
        if let animation = cache[sticker.code] { return animation }
        if let task = pending[sticker.code] { return await task.value }
        let task = Task.detached(priority: .utility) { await Self.download(sticker) }
        pending[sticker.code] = task
        let animation = await task.value
        pending[sticker.code] = nil
        if let animation {
            while cache.count >= 24 || cache.values.reduce(0,{ $0 + $1.frames.count * 96 * 96 * 4 }) + animation.frames.count * 96 * 96 * 4 > 16_000_000 {
                guard let key = cache.keys.first else { break }; cache[key] = nil
            }
            cache[sticker.code] = animation
        }
        return animation
    }

    private static func download(_ sticker: ForumSticker) async -> StickerAnimation? {
        #if DEBUG
        if let fixtureResponses {
            guard let data = fixtureResponses[sticker.url.absoluteString] else { return nil }
            return sticker.isVideo ? await decodeVideo(data) : decodeImage(data)
        }
        #endif
        do {
            try await ImageWorkLimiter.shared.acquire()
            defer { Task { await ImageWorkLimiter.shared.release() } }
            try Task.checkCancellation()
            var request = URLRequest(url: sticker.url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 8_000_000 else { return nil }
            if sticker.isVideo { return await decodeVideo(data) }
            return decodeImage(data)
        } catch { return nil }
    }

    private static func decodeImage(_ data: Data) -> StickerAnimation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var frames: [CGImage] = []
        var durations: [TimeInterval] = []
        for index in 0..<min(CGImageSourceGetCount(source), 120) {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 96]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1
            frames.append(image)
            durations.append(max(delay, 0.02))
        }
        return frames.isEmpty ? nil : StickerAnimation(frames: frames, durations: durations)
    }

    private static func decodeVideo(_ data: Data) async -> StickerAnimation? {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".mov")
        do {
            try data.write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let asset = AVURLAsset(url: file)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { return nil }
            let step = max(0.1, duration / 60)
            let times = stride(from: 0.0, to: duration, by: step).map { CMTime(seconds: $0, preferredTimescale: 600) }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = CGSize(width: 96, height: 96)
            generator.appliesPreferredTrackTransform = true
            var samples: [(Double, CGImage)] = []
            for await result in generator.images(for: times) {
                if case let .success(requestedTime, image, _) = result { samples.append((requestedTime.seconds, image)) }
            }
            let frames = samples.sorted { $0.0 < $1.0 }.map(\.1)
            return frames.isEmpty ? nil : StickerAnimation(frames: frames, durations: Array(repeating: step, count: frames.count))
        } catch { return nil }
    }
}
