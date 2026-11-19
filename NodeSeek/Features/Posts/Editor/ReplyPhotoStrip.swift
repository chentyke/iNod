import NodeSeekClient
import SwiftUI

struct ReplyPhotoStrip: View {
    let images: [URL]
    let remove: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(images.indices, id: \.self) { index in
                    ReplyPhotoThumbnail(url: images[index])
                        .overlay(alignment: .topTrailing) {
                            Button { remove(index) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body.weight(.medium))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.65))
                                    .padding(4)
                                    .frame(width: 44, height: 44, alignment: .topTrailing)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("移除第 \(index + 1) 张图片")
                        }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct ReplyPhotoThumbnail: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color.seekTray
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            let thumbnail = try? await ForumImageLoader.shared.load(url, size: .thumbnail, prioritized: true)
            if !Task.isCancelled { image = thumbnail }
        }
    }
}
