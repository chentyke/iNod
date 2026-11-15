import SwiftUI

struct ImageViewer: View {
    let gallery: ImageGallery
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var zoomedPage: Int?

    init(gallery: ImageGallery) {
        self.gallery = gallery
        _currentIndex = State(initialValue: gallery.startIndex)
    }

    var body: some View {
        NavigationStack {
            Group {
                if gallery.items.count > 1 {
                    TabView(selection: $currentIndex) {
                        ForEach(gallery.items.indices, id: \.self) { index in
                            page(at: index)
                                .clipped()
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .scrollDisabled(zoomedPage == currentIndex)
                } else {
                    page(at: currentIndex)
                        .clipped()
                }
            }
            .background { Color.black.ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                if gallery.items.count > 1 {
                    ToolbarItem(placement: .principal) { pageCounter }
                }
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: gallery.items[currentIndex].url) }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private var pageCounter: some View {
        Text("\(currentIndex + 1) / \(gallery.items.count)")
            .font(.subheadline.monospacedDigit())
            .accessibilityIdentifier("image-gallery-position")
            .accessibilityLabel("图片")
            .accessibilityValue("第 \(currentIndex + 1) 张，共 \(gallery.items.count) 张")
            .accessibilityAdjustableAction { direction in
                let next: Int
                switch direction {
                case .increment: next = currentIndex + 1
                case .decrement: next = currentIndex - 1
                @unknown default: return
                }
                guard gallery.items.indices.contains(next) else { return }
                currentIndex = next
            }
    }

    private func page(at index: Int) -> some View {
        let item = gallery.items[index]
        return ForumImageContent(url: item.url, initialImage: index == gallery.startIndex ? gallery.initialImage : nil) { image in
            ZoomableForumImage(image: image, label: item.label, isCurrent: index == currentIndex) { isZoomed in
                if isZoomed { zoomedPage = index }
                else if zoomedPage == index { zoomedPage = nil }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
