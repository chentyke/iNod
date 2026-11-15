import Foundation
import NodeSeekClient
import NodeSeekCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum NodeImageInput {
    case photo(PhotosPickerItem)
    case file(URL)
    case provider(NSItemProvider)

    @MainActor
    func prepare() async throws -> PreparedUploadImage {
        switch self {
        case .photo(let photo):
            guard let data = try await photo.loadTransferable(type: Data.self) else {
                throw SiteError.message("无法读取这张照片。")
            }
            return try await Self.prepare(data)
        case .file(let url):
            return try await Task.detached(priority: .userInitiated) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size <= UploadImageProcessor.maximumInputBytes else {
                    throw SiteError.message("请选择 20 MB 以内的图片文件。")
                }
                return try UploadImageProcessor.prepare(Data(contentsOf: url, options: .mappedIfSafe))
            }.value
        case .provider(let provider):
            guard let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }) else {
                throw SiteError.message("无法读取剪贴板中的图片。")
            }
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                    if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: error ?? SiteError.message("无法读取这张图片。")) }
                }
            }
            return try await Self.prepare(data)
        }
    }

    private static func prepare(_ data: Data) async throws -> PreparedUploadImage {
        try await Task.detached(priority: .userInitiated) { try UploadImageProcessor.prepare(data) }.value
    }
}
