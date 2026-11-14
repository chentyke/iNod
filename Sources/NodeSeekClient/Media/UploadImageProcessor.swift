import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PreparedUploadImage: Sendable { public let image: CGImage; public let png: Data }

public enum UploadImageProcessor {
    public static func prepare(_ data: Data) throws -> PreparedUploadImage {
        guard data.count <= 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) else {
            throw SiteError.message("请选择 20 MB 以内的图片。")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw SiteError.invalidResponse }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 10_000_000 else { throw SiteError.message("处理后的图片仍大于 10 MB，请选择较小的图片。") }
        return PreparedUploadImage(image: image, png: output as Data)
    }
}
