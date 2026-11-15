import NodeSeekClient
import SwiftUI

struct ForumImageView: View {
    let url: URL
    let alt: String
    @Environment(\.defersForumImagesUntilVisible) private var defersLoading
    @State private var hasBeenVisible = false
    @State private var image: CGImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var showsViewer = false

    private var canLoad: Bool { !defersLoading || hasBeenVisible }

    var body: some View {
        Group {
            if let image {
                Image(image, scale: 1, label: Text(alt.isEmpty ? "帖子图片" : alt)).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
                    .onTapGesture { showsViewer = true }
                    .accessibilityAddTraits(.isButton).accessibilityHint("点按放大图片")
                    .accessibilityAction { showsViewer = true }
            } else if failed {
                VStack(spacing: 12) {
                    Label("图片暂时无法加载", systemImage: "photo").foregroundStyle(.secondary)
                    Button("重试") { attempt += 1 }
                }.frame(maxWidth: .infinity).padding(24).background(Color.seekSurface, in: .rect(cornerRadius: 12))
            } else { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
        }
        .fullScreenCover(isPresented:$showsViewer) { if let image { ImageViewer(image:image,url:url,alt:alt) } }
        .onScrollVisibilityChange(threshold: 0.01) { visible in
            if defersLoading, visible { hasBeenVisible = true }
        }
        .task(id: "\(url.absoluteString)|\(attempt)|\(canLoad)") {
            guard canLoad else { return }
            failed = false
            do {
                let result = try await ForumImageLoader.shared.load(url)
                try Task.checkCancellation()
                image = result
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

extension EnvironmentValues {
    @Entry var defersForumImagesUntilVisible = false
}
