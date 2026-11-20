import SwiftUI

struct ImageViewer: View {
    let gallery: ImageGallery
    let initialImageIsThumbnail: Bool
    let postTitle: String?
    let onOpenFloor: ((Int) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex: Int
    @State private var zoomedPage: Int?
    @State private var showsControls = true
    @State private var savedURLs: Set<URL> = []

    init(gallery: ImageGallery, initialImageIsThumbnail: Bool = false, postTitle: String? = nil,
         onOpenFloor: ((Int) -> Void)? = nil) {
        self.postTitle = postTitle
        self.onOpenFloor = onOpenFloor
        self.gallery = gallery
        self.initialImageIsThumbnail = initialImageIsThumbnail
        _currentIndex = State(initialValue: gallery.startIndex)
    }

    var body: some View {
        if reduceMotion { viewer }
        else { viewer.navigationTransition(.zoom(sourceID: gallery.source, in: gallery.source)) }
    }

    private var viewer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if gallery.items.count > 1 {
                TabView(selection: $currentIndex) {
                    ForEach(gallery.items.indices, id: \.self) { index in
                        page(at: index).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .scrollDisabled(zoomedPage == currentIndex)
                .ignoresSafeArea()
            } else {
                page(at: currentIndex).ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) { if showsControls { controls } }
        .overlay(alignment: .bottomLeading) { if showsControls { caption } }
        .preferredColorScheme(.dark)
        .statusBarHidden(!showsControls)
        .persistentSystemOverlays(showsControls ? .automatic : .hidden)
        .interactiveDismissDisabled(zoomedPage == currentIndex)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 8) {
            HStack {
                Button { dismiss() } label: {
                    Image(.inkClose).frame(width: 44, height: 44).contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("完成")
                .keyboardShortcut(.cancelAction)
                Spacer()
                ImageViewerActions(item: gallery.items[currentIndex], savedURLs: $savedURLs)
                    .id(currentIndex)
            }
            .overlay {
                if gallery.items.count > 1 {
                    pageCounter
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .glassEffect(.regular, in: .capsule)
                }
            }
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    @ViewBuilder private var caption: some View {
        let item = gallery.items[currentIndex]
        if let source = item.attribution, let onOpenFloor {
            ImageSourceButton(source: source, caption: source.excerpt ?? postTitle) {
                onOpenFloor(source.floor)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        } else if !item.alt.isEmpty {
            Text(verbatim: item.alt).font(.body).lineLimit(2)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .padding(.horizontal, 16).padding(.bottom, 8)
                .allowsHitTesting(false)
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
        let initialImage = index == gallery.startIndex ? gallery.initialImage : nil
        return ForumImageContent(url: item.url,
                                 initialImage: initialImageIsThumbnail ? nil : initialImage,
                                 previewImage: initialImageIsThumbnail ? initialImage : nil,
                                 prioritized: index == currentIndex) { image in
            ZoomableForumImage(image: image, label: item.label,
                               isCurrent: index == currentIndex) { isZoomed in
                if isZoomed { zoomedPage = index }
                else if zoomedPage == index { zoomedPage = nil }
            } onDismiss: {
                dismiss()
            } onTap: {
                withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) { showsControls.toggle() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
