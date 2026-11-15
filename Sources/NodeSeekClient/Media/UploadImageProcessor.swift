import CoreText
import Foundation
import ImageIO
import NodeSeekCore
import UniformTypeIdentifiers

public struct PreparedUploadImage: Sendable { public let image: CGImage; public let png: Data }

public struct UploadImageOptions: Sendable {
    public let quality: Double?
    public let watermark: String

    public init(quality: Double? = nil, watermark: String = "") {
        self.quality = quality.flatMap { $0.isFinite ? min(1, max(0.1, $0)) : nil }
        self.watermark = watermark
    }
}

public enum UploadImageProcessor {
    public static let maximumInputBytes = 20_000_000
    private static let maximumUploadBytes = 10_000_000

    public static func prepare(_ data: Data) throws -> PreparedUploadImage {
        guard data.count <= maximumInputBytes, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) else {
            throw SiteError.message("请选择 20 MB 以内的图片。")
        }
        let png = try encode(image, as: .png, limit: maximumInputBytes)
        let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320
        ] as CFDictionary)
        return PreparedUploadImage(image: preview ?? image, png: png)
    }

    public static func render(_ input: PreparedUploadImage, options: UploadImageOptions) throws -> (data: Data, format: NodeImageAPI.ImageFormat) {
        guard options.quality != nil || !options.watermark.isEmpty else {
            guard input.png.count <= maximumUploadBytes else { throw imageTooLarge }
            return (input.png, .png)
        }
        guard let source = CGImageSourceCreateWithData(input.png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SiteError.message("无法处理这张图片。")
        }

        let preservesAlpha = hasAlpha(image)
        // JPEG cannot carry transparency. Resize transparent images before encoding them as PNG.
        let scale = preservesAlpha ? options.quality.map { sqrt(max(0.25, $0)) } ?? 1 : 1
        let output = try drawing(image, scale: scale, watermark: options.watermark)
        let format: NodeImageAPI.ImageFormat = options.quality != nil && !preservesAlpha ? .jpeg : .png
        return (try encode(output, as: format, quality: options.quality, limit: maximumUploadBytes), format)
    }

    public static func preview(_ input: PreparedUploadImage, watermark: String) -> CGImage {
        (try? drawing(input.image, scale: 1, watermark: watermark)) ?? input.image
    }

    private static var imageTooLarge: SiteError { .message("处理后的图片仍大于 10 MB，请降低压缩质量或选择较小的图片。") }

    private static func encode(_ image: CGImage, as format: NodeImageAPI.ImageFormat, quality: Double? = nil, limit: Int) throws -> Data {
        let output = NSMutableData()
        let type = format == .jpeg ? UTType.jpeg : UTType.png
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw SiteError.message("无法保存处理后的图片。")
        }
        let properties: CFDictionary? = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: quality ?? 0.85] as CFDictionary : nil
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw SiteError.message("无法保存处理后的图片。") }
        guard output.length <= limit else { throw imageTooLarge }
        return output as Data
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    private static func drawing(_ image: CGImage, scale: Double, watermark: String) throws -> CGImage {
        guard scale < 1 || !watermark.isEmpty else { return image }
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let size = CGSize(width: width, height: height)
        let alpha = hasAlpha(image) ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue) else {
            throw SiteError.message("无法处理这张图片。")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        if !watermark.isEmpty { drawWatermark(watermark, on: context, size: size) }
        guard let result = context.makeImage() else { throw SiteError.message("无法处理这张图片。") }
        return result
    }

    private static func drawWatermark(_ text: String, on context: CGContext, size: CGSize) {
        let fontSize = min(96, max(8, min(size.width, size.height) * 0.045))
        let margin = min(size.width, size.height) * 0.04
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: [
                .init(kCTFontAttributeName as String): font,
                .init(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.95)
            ]
        ))
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, &descent, nil))
        let scale = min(1, (size.width - margin * 2) / max(1, width), (size.height - margin * 2) / (fontSize + descent))
        context.saveGState()
        context.translateBy(x: size.width - margin - width * scale, y: margin + descent * scale)
        context.scaleBy(x: scale, y: scale)
        context.setShadow(offset: .zero, blur: fontSize * 0.2, color: CGColor(gray: 0, alpha: 0.9))
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
