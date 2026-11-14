import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct StickerThumbnail: View {
    let sticker: ForumSticker
    @State private var frame: CGImage?
    var body: some View {
        Group {
            if let frame { Image(decorative: frame, scale: 1).resizable().scaledToFit() }
            else { Text(sticker.code).font(.caption).foregroundStyle(.secondary) }
        }.frame(width: 52, height: 52)
        .task(id: sticker.code) {
            if let image = await StickerThumbnailLoader.shared.load(sticker) {
                guard !Task.isCancelled else { return }
                frame = image
            }
        }
    }
}
