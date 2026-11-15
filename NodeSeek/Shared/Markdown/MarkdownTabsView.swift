import NodeSeekCore
import SwiftUI

struct MarkdownTabsView<Embedded: View>: View {
    let tabs: [MarkdownTab]
    var loadsBlocksOnScroll = false
    let onOpenImages: (ImageGallery) -> Void
    @ViewBuilder var embedded: (MarkdownBlock) -> Embedded
    @State private var selection = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize || tabs.count > 4 {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
            }
            if tabs.indices.contains(selection) {
                let index = selection
                MarkdownContent(markdown: tabs[index].markdown, loadsBlocksOnScroll: loadsBlocksOnScroll,
                                onOpenImages: { gallery in
                    onOpenImages(gallery.adding(
                        before: tabs[..<index].flatMap { ImageGallery.images(in: $0.markdown) },
                        after: tabs[(index + 1)...].flatMap { ImageGallery.images(in: $0.markdown) }
                    ))
                }, embedded: embedded)
                .id(index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var picker: some View {
        Picker("内容分组", selection: $selection) {
            ForEach(tabs.indices, id: \.self) { index in
                Text(tabs[index].title).tag(index)
            }
        }
    }
}
