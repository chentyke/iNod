import CoreGraphics
import Foundation
import ImageIO
import NodeSeekCore
import Testing
import UniformTypeIdentifiers
@testable import NodeSeekClient

@Test func nodeImagePreservesThePreparedPNGWhenProcessingIsOff() throws {
    let input = try UploadImageProcessor.prepare(testPNG(transparent: false))
    let result = try UploadImageProcessor.render(input, options: .init())
    #expect(result.format == .png)
    #expect(result.data == input.png)
}

@Test func nodeImageCompressesOpaqueImagesToJPEG() throws {
    let input = try UploadImageProcessor.prepare(testPNG(transparent: false))
    let result = try UploadImageProcessor.render(input, options: .init(quality: 0.65))
    #expect(result.format == .jpeg)
    #expect(result.data.starts(with: [0xff, 0xd8]))
    let source = try #require(CGImageSourceCreateWithData(result.data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 160 && image.height == 120)
}

@Test func nodeImageWatermarksAndPreservesTransparencyWithCompression() throws {
    let input = try UploadImageProcessor.prepare(testPNG(transparent: true))
    let watermark = "nodeimage.com  测试"
    let result = try UploadImageProcessor.render(input, options: .init(quality: 0.36, watermark: watermark))
    #expect(result.format == .png)
    let source = try #require(CGImageSourceCreateWithData(result.data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 96 && image.height == 72)
    #expect(image.alphaInfo == .last || image.alphaInfo == .premultipliedLast)
    let preview = UploadImageProcessor.preview(input, watermark: watermark)
    let originalBytes = try #require(input.image.dataProvider?.data) as Data
    let previewBytes = try #require(preview.dataProvider?.data) as Data
    #expect(previewBytes != originalBytes)
}

private func testPNG(transparent: Bool) throws -> Data {
    let alpha: CGImageAlphaInfo = transparent ? .premultipliedLast : .noneSkipLast
    let context = try #require(CGContext(data: nil, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alpha.rawValue))
    context.setFillColor(red: 0.1, green: 0.35, blue: 0.7, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: transparent ? 80 : 160, height: 120))
    let image = try #require(context.makeImage())
    let png = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return png as Data
}
