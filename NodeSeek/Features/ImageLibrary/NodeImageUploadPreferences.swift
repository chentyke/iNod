import NodeSeekClient
import NodeSeekCore
import SwiftUI

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
    }

    var deleteAfterDays: Int? { autoDelete ? deleteDays : nil }

    func imageOptions(username: String?) -> UploadImageOptions {
        let watermark = addWatermark ? [
            watermarkWebsite ? "nodeimage.com" : nil,
            watermarkUsername ? username : nil
        ].compactMap { $0 }.joined(separator: "  ") : ""
        return UploadImageOptions(quality: compressImages ? compressionQuality / 100 : nil, watermark: watermark)
    }
}
