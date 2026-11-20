import NodeSeekClient
import SwiftUI

struct ForumImageView: View {
    let url: URL
    let alt: String
    var size: ForumImageLoader.Size = .full
    var onOpenImages: ((ImageGallery) -> Void)?
    @Environment(\.defersForumImagesUntilVisible) private var defersLoading
    @Namespace private var source
    @State private var gallery: ImageGallery?

    var body: some View {
        let item = ImageGallery.Item(url: url, alt: alt)
        ForumImageContent(url: url, size: size, defersLoading: defersLoading, prioritized: defersLoading || size == .thumbnail) { image in
            Button {
                let opened = ImageGallery(items: [item], startIndex: 0, initialImage: image, source: source)
                if let onOpenImages { onOpenImages(opened) }
                else { gallery = opened }
            } label: {
                Image(image, scale: 1, label: Text(verbatim: item.label)).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
            }
            .matchedTransitionSource(id: source, in: source) { $0.clipShape(.rect(cornerRadius: 12)) }
            .buttonStyle(.plain)
            .accessibilityHint("打开全屏图片")
        }
        .id(url)
        .fullScreenCover(item: $gallery) { ImageViewer(gallery: $0, initialImageIsThumbnail: size == .thumbnail) }
    }
}

struct ForumImageContent<Content: View>: View {
    let url: URL
    var size: ForumImageLoader.Size = .full
    var initialImage: CGImage?
    var previewImage: CGImage?
    var defersLoading = false
    var prioritized = false
    @ViewBuilder var content: (CGImage) -> Content
    @State private var hasBeenVisible = false
    @State private var image: CGImage?
    @State private var failed = false
    @State private var attempt = 0

    private var canLoad: Bool { !defersLoading || hasBeenVisible }

    var body: some View {
        Group {
            if let image = initialImage ?? image ?? previewImage {
                content(image)
                    .overlay(alignment: .bottom) {
                        if failed {
                            Button("重试") { attempt += 1 }
                                .buttonStyle(.glass)
                                .padding(.bottom, 12)
                        }
                    }
            } else if failed {
                VStack(spacing: 12) {
                    Label("图片暂时无法加载", image: .inkBrokenPhoto).foregroundStyle(.secondary)
                    Button("重试") { attempt += 1 }
                }.frame(maxWidth: .infinity).padding(24).background(Color.seekSurface, in: .rect(cornerRadius: 12))
            } else { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
        }
        .onScrollVisibilityChange(threshold: 0.01) { visible in
            if defersLoading, visible { hasBeenVisible = true }
        }
        .task(id: canLoad ? attempt : nil) {
            guard canLoad, initialImage == nil, image == nil else { return }
            failed = false
            do {
                let result = try await ForumImageLoader.shared.load(url, size: size, prioritized: prioritized)
                try Task.checkCancellation()
                image = result
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

extension EnvironmentValues {
    @Entry var defersForumImagesUntilVisible = false
}
