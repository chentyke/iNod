import NodeSeekClient
import Photos
import SwiftUI

struct ImageViewerActions: View {
    let item: ImageGallery.Item
    @Binding var savedURLs: Set<URL>
    private var saved: Bool { savedURLs.contains(item.url) }

    private enum Action { case save, share }
    @State private var action: Action?
    @State private var share: SharedPhoto?
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            actionButton(.save, symbol: saved ? "checkmark" : "square.and.arrow.down",
                         label: saved ? "已保存到相册" : "保存图片")
                .disabled(saved)
            actionButton(.share, symbol: "square.and.arrow.up", label: "分享图片")
        }
        .buttonStyle(.plain)
        .disabled(action != nil)
        .glassEffect(.regular.interactive(), in: .capsule)
        .task(id: action) {
            guard let action else { return }
            await perform(action)
        }
        .sheet(item: $share) { ImageShareSheet(photo: $0) }
        .alert("图片操作未完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func actionButton(_ selection: Action, symbol: String, label: String) -> some View {
        Button { action = selection } label: {
            Group {
                if action == selection { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: symbol)
                        .resizable().scaledToFit()
                        .frame(width: 18, height: 19)
                }
            }
            .frame(width: 44, height: 44).contentShape(.rect)
        }
        .accessibilityLabel(label)
    }

    private func perform(_ selected: Action) async {
        defer { action = nil }
        do {
            let original = try await ForumImageLoader.shared.originalImage(for: item.url)
            try Task.checkCancellation()
            switch selected {
            case .share:
                share = SharedPhoto(original: original, title: item.label, filename: item.url.deletingPathExtension().lastPathComponent)
            case .save:
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                try Task.checkCancellation()
                guard status == .authorized || status == .limited else {
                    errorMessage = "请在系统设置中允许 iNod 添加照片，再试一次。"
                    return
                }
                try await PHPhotoLibrary.shared().performChanges { @Sendable in
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = original.type.identifier
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: original.data, options: options)
                }
                savedURLs.insert(item.url)
                UIAccessibility.post(notification: .announcement, argument: "已保存到相册")
            }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}

private struct SharedPhoto: Identifiable {
    let id = UUID()
    let original: ForumImageLoader.OriginalImage
    let title: String
    let filename: String
}

private struct ImageShareSheet: UIViewControllerRepresentable {
    let photo: SharedPhoto

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let provider = NSItemProvider()
        provider.suggestedName = photo.filename.isEmpty ? "图片" : photo.filename
        let original = photo.original
        provider.registerDataRepresentation(forTypeIdentifier: original.type.identifier, visibility: .all) { @Sendable completion in
            completion(original.data, nil)
            return nil
        }
        let items = UIActivityItemsConfiguration(itemProviders: [provider])
        let title = photo.title
        items.metadataProvider = { key in key == .title ? title : nil }
        items.previewProvider = { _, _, _ in provider }
        return UIActivityViewController(activityItemsConfiguration: items)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
