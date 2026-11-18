import Foundation
import NodeSeekCore
import Testing

@Test func hostedImageExtractsNormalizedFormatBadge() throws {
    let png = HostedImage(
        id: "img_1",
        filename: "bench-latency-chart.png",
        url: URL(string: "https://cdn.nodeimage.com/i/bench-latency-chart.png")!
    )
    #expect(png.formatBadge == "PNG")

    let jpeg = HostedImage(
        id: "img_2",
        filename: "photo.JPEG",
        url: URL(string: "https://cdn.nodeimage.com/i/photo.JPEG")!
    )
    #expect(jpeg.formatBadge == "JPG")

    let fallbackToURL = HostedImage(
        id: "img_3",
        filename: "screenshot_without_ext",
        url: URL(string: "https://cdn.nodeimage.com/i/abc123.webp")!
    )
    #expect(fallbackToURL.formatBadge == "WEBP")

    let missing = HostedImage(
        id: "img_4",
        filename: "plain",
        url: URL(string: "https://cdn.nodeimage.com/i/plain")!
    )
    #expect(missing.formatBadge == nil)
}

@Test func nodeImageAPIMasksKeysWithoutExposingMiddleCharacters() {
    #expect(NodeImageAPI.maskedKey("") == "")
    #expect(NodeImageAPI.maskedKey("   \n ") == "")
    #expect(NodeImageAPI.maskedKey("12345678") == "••••••••")
    let key = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
    #expect(NodeImageAPI.maskedKey("  \(key) \n") == "a1b2••••8f90")
}

@Test func nodeImageUploadConfigSummarizesAndValidatesOptions() {
    let defaults = NodeImageUploadConfig()
    #expect(defaults.isDefault)
    #expect(!defaults.hasActiveProcessing(username: "林风"))
    #expect(defaults.normalizedQualityFraction == nil)
    #expect(defaults.deleteAfterDays == nil)
    #expect(defaults.watermarkText(username: "林风").isEmpty)
    #expect(defaults.summaryItems(username: "林风") == ["原图", "长期保留", "默认 直链"])

    var custom = NodeImageUploadConfig(
        compressImages: true,
        compressionQuality: 75,
        addWatermark: true,
        watermarkWebsite: true,
        watermarkUsername: true,
        copyAfterUpload: true,
        linkFormat: .markdown,
        autoDelete: true,
        deleteDays: 7
    )
    #expect(!custom.isDefault)
    #expect(custom.hasActiveProcessing(username: "林风"))
    #expect(custom.normalizedQualityFraction == 0.75)
    #expect(custom.deleteAfterDays == 7)
    #expect(custom.watermarkText(username: "林风") == "nodeimage.com  林风")
    #expect(custom.summaryItems(username: "林风") == ["压缩 75%", "水印", "7 天后删除", "自动复制 Markdown"])

    custom.watermarkWebsite = false
    custom.watermarkUsername = false
    #expect(custom.hasMissingWatermarkContent)
    #expect(custom.watermarkText(username: "林风").isEmpty)
    #expect(!custom.summaryItems(username: "林风").contains("水印"))

    custom.compressionQuality = 140
    custom.deleteDays = 999
    #expect(custom.clampedQuality == 100)
    #expect(custom.deleteAfterDays == 365)
}
