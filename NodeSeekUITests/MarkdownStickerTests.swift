import UIKit
import XCTest

@MainActor
final class MarkdownStickerTests: XCTestCase {
    func testPostHeadingShowsAnInlineSticker() throws {
        let size = CGSize(width: 24, height: 24)
        let sticker = UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let app = ForumFixture.launch(
            opensThread: true,
            openingMarkdown: "# 周六下午两点见 :xhj031: 记得带书",
            assetResponses: ["https://www.nodeseek.com/static/image/sticker/xhj/031.png": sticker]
        )

        let heading = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label ENDSWITH %@ AND NOT (label CONTAINS %@)",
            "周六下午两点见", "记得带书", ":xhj031:"
        )).firstMatch
        guard heading.waitForExistence(timeout: 8) else {
            return XCTFail("The heading should keep its words and replace the sticker code.")
        }

        let screenshot = try XCTUnwrap(heading.screenshot().image.cgImage)
        XCTAssertTrue(containsMagenta(in: screenshot), "The heading should draw the test sticker.")
    }

    private func containsMagenta(in image: CGImage) -> Bool {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else { return false }
            context.draw(image, in: bounds)
            return true
        }
        return drawn && stride(from: 0, to: pixels.count, by: 4).contains { index in
            pixels[index] > 220 && pixels[index + 1] < 35 && pixels[index + 2] > 220
        }
    }
}
