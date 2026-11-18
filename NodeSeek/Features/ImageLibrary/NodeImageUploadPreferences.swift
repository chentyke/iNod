import NodeSeekClient
import NodeSeekCore
import SwiftUI

enum NodeImageLibraryLayout: String, CaseIterable, Sendable {
    case list
    case grid
}

struct NodeImageUploadPreferences: DynamicProperty {
    @AppStorage var copyAfterUpload: Bool
    @AppStorage var linkFormat: HostedImageLinkFormat
    @AppStorage var autoDelete: Bool
    @AppStorage var deleteDays: Int
    @AppStorage var compressImages: Bool
    @AppStorage var compressionQuality: Double
    @AppStorage var addWatermark: Bool
    @AppStorage var watermarkWebsite: Bool
    @AppStorage var watermarkUsername: Bool
    @AppStorage var layoutMode: NodeImageLibraryLayout

    init(userID: Int) {
        _copyAfterUpload = AppStorage(wrappedValue: false, "nodeImage.copyAfterUpload.\(userID)")
        _linkFormat = AppStorage(wrappedValue: .direct, "nodeImage.linkFormat.\(userID)")
        _autoDelete = AppStorage(wrappedValue: false, "nodeImage.autoDelete.\(userID)")
        _deleteDays = AppStorage(wrappedValue: 30, "nodeImage.deleteDays.\(userID)")
        _compressImages = AppStorage(wrappedValue: false, "nodeImage.compressImages.\(userID)")
        _compressionQuality = AppStorage(wrappedValue: 85, "nodeImage.compressionQuality.\(userID)")
        _addWatermark = AppStorage(wrappedValue: false, "nodeImage.addWatermark.\(userID)")
        _watermarkWebsite = AppStorage(wrappedValue: true, "nodeImage.watermarkWebsite.\(userID)")
        _watermarkUsername = AppStorage(wrappedValue: false, "nodeImage.watermarkUsername.\(userID)")
        _layoutMode = AppStorage(wrappedValue: .list, "nodeImage.layoutMode.\(userID)")
    }

    var config: NodeImageUploadConfig {
        NodeImageUploadConfig(
            compressImages: compressImages,
            compressionQuality: compressionQuality,
            addWatermark: addWatermark,
            watermarkWebsite: watermarkWebsite,
            watermarkUsername: watermarkUsername,
            copyAfterUpload: copyAfterUpload,
            linkFormat: linkFormat,
            autoDelete: autoDelete,
            deleteDays: deleteDays
        )
    }

    var deleteAfterDays: Int? {
        config.deleteAfterDays
    }

    func imageOptions(username: String?) -> UploadImageOptions {
        let current = config
        return UploadImageOptions(
            quality: current.normalizedQualityFraction,
            watermark: current.watermarkText(username: username)
        )
    }

    func resetToDefaults() {
        let defaults = NodeImageUploadConfig()
        compressImages = defaults.compressImages
        compressionQuality = defaults.compressionQuality
        addWatermark = defaults.addWatermark
        watermarkWebsite = defaults.watermarkWebsite
        watermarkUsername = defaults.watermarkUsername
        copyAfterUpload = defaults.copyAfterUpload
        linkFormat = defaults.linkFormat
        autoDelete = defaults.autoDelete
        deleteDays = defaults.deleteDays
    }
}
