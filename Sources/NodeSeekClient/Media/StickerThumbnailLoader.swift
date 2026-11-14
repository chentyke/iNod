import NodeSeekCore
import Foundation
import ImageIO
import AVFoundation

public actor StickerThumbnailLoader {
    public static let shared = StickerThumbnailLoader()
    private var cache: [String:CGImage] = [:]
    private var pending: [String:Task<CGImage?,Never>] = [:]
    public func load(_ sticker: ForumSticker) async -> CGImage? {
        if let image = cache[sticker.code] { return image }
        if let task = pending[sticker.code] { return await task.value }
        let task = Task.detached(priority:.utility) { await Self.download(sticker) }; pending[sticker.code] = task
        let image = await task.value; pending[sticker.code] = nil
        if let image { if cache.count >= 128,let key = cache.keys.first { cache.removeValue(forKey:key) }; cache[sticker.code] = image }
        return image
    }
    private static func download(_ sticker: ForumSticker) async -> CGImage? {
        do {
            try await ImageWorkLimiter.shared.acquire()
            defer { Task { await ImageWorkLimiter.shared.release() } }
            try Task.checkCancellation()
            let (data,response) = try await URLSession.shared.data(for:ForumImageRequest.make(url:sticker.url))
            guard (response as? HTTPURLResponse)?.statusCode == 200,data.count < 8_000_000 else { return nil }
            if !sticker.isVideo {
                guard let source = CGImageSourceCreateWithData(data as CFData,nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:96] as CFDictionary)
            }
            let file = FileManager.default.temporaryDirectory.appending(path:UUID().uuidString + ".mov")
            try data.write(to:file); defer { try? FileManager.default.removeItem(at:file) }
            let generator = AVAssetImageGenerator(asset:AVURLAsset(url:file)); generator.maximumSize = CGSize(width:96,height:96); generator.appliesPreferredTrackTransform = true
            return try await generator.image(at:.zero).image
        } catch { return nil }
    }
}
