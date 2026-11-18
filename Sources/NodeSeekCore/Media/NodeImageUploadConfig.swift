import Foundation

public struct NodeImageUploadConfig: Equatable, Sendable {
    public static let expirationPresets = [1, 7, 30, 90, 180, 365]

    public var compressImages: Bool
    public var compressionQuality: Double
    public var addWatermark: Bool
    public var watermarkWebsite: Bool
    public var watermarkUsername: Bool
    public var copyAfterUpload: Bool
    public var linkFormat: HostedImageLinkFormat
    public var autoDelete: Bool
    public var deleteDays: Int

    public init(
        compressImages: Bool = false,
        compressionQuality: Double = 85,
        addWatermark: Bool = false,
        watermarkWebsite: Bool = true,
        watermarkUsername: Bool = false,
        copyAfterUpload: Bool = false,
        linkFormat: HostedImageLinkFormat = .direct,
        autoDelete: Bool = false,
        deleteDays: Int = 30
    ) {
        self.compressImages = compressImages
        self.compressionQuality = compressionQuality
        self.addWatermark = addWatermark
        self.watermarkWebsite = watermarkWebsite
        self.watermarkUsername = watermarkUsername
        self.copyAfterUpload = copyAfterUpload
        self.linkFormat = linkFormat
        self.autoDelete = autoDelete
        self.deleteDays = deleteDays
    }

    public var clampedQuality: Int {
        guard compressionQuality.isFinite else { return 85 }
        return min(100, max(10, Int(compressionQuality.rounded())))
    }

    public var normalizedQualityFraction: Double? {
        compressImages ? Double(clampedQuality) / 100.0 : nil
    }

    public var clampedDeleteDays: Int {
        min(365, max(1, deleteDays))
    }

    public var deleteAfterDays: Int? {
        autoDelete ? clampedDeleteDays : nil
    }

    public var hasMissingWatermarkContent: Bool {
        addWatermark && !watermarkWebsite && !watermarkUsername
    }

    public var isDefault: Bool {
        self == Self()
    }

    public func watermarkText(username: String?) -> String {
        guard addWatermark else { return "" }
        let trimmedUser = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            watermarkWebsite ? "nodeimage.com" : nil,
            (watermarkUsername && trimmedUser?.isEmpty == false) ? trimmedUser : nil
        ].compactMap { $0 }.joined(separator: "  ")
    }

    public func hasActiveProcessing(username: String?) -> Bool {
        compressImages || !watermarkText(username: username).isEmpty || autoDelete || copyAfterUpload
    }

    public func summaryItems(username: String?) -> [String] {
        var items = [compressImages ? "压缩 \(clampedQuality)%" : "原图"]
        if !watermarkText(username: username).isEmpty {
            items.append("水印")
        }
        items.append(autoDelete ? "\(clampedDeleteDays) 天后删除" : "长期保留")
        items.append(copyAfterUpload ? "自动复制 \(linkFormat.title)" : "默认 \(linkFormat.title)")
        return items
    }
}
