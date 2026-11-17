import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct InlineStickerText: View {
    let markdown: String
    var expands = true
    var trailingLabel: Text?
    var font: Font = .body
    var lineSpacing: CGFloat = 5
    @Environment(\.forumDocumentURL) private var documentURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var stickerSize = 32.0
    @State private var animations: [String: StickerAnimation] = [:]

    private enum RenderSegment {
        case text(Text, hasLinks: Bool)
        case sticker(ForumSticker)

        var hasLinks: Bool {
            if case .text(_, let hasLinks) = self { return hasLinks }
            return false
        }
    }

    var body: some View {
        let segments = InlineContent.parse(markdown)
        if segments.contains(where: { if case .sticker = $0 { true } else { false } }) {
            let prepared: [RenderSegment] = segments.map { segment in
                switch segment {
                case .text(let value):
                    let text = ForumText.attributed(value, baseURL: documentURL)
                    return .text(Text(text), hasLinks: text.runs.contains { $0.link != nil })
                case .sticker(let sticker): return .sticker(sticker)
                }
            }
            let hasLinks = prepared.contains(where: \.hasLinks)
            TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion || !animations.values.contains { $0.isAnimated })) { context in
                TextWithTrailingLabel(text: rendered(prepared, at: context.date).font(font), label: trailingLabel,
                                      hasLinks: hasLinks)
                    .lineSpacing(lineSpacing)
                    .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
            }
            .task(id: markdown) {
                for segment in segments {
                    guard case let .sticker(sticker) = segment, animations[sticker.code] == nil else { continue }
                    if let animation = await StickerLoader.shared.load(sticker) {
                        guard !Task.isCancelled else { return }
                        animations[sticker.code] = animation
                    }
                }
            }
        } else {
            let text = ForumText.attributed(markdown, baseURL: documentURL)
            TextWithTrailingLabel(text: Text(text).font(font), label: trailingLabel,
                                  hasLinks: text.runs.contains { $0.link != nil })
                .lineSpacing(lineSpacing)
                .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
        }
    }

    private func rendered(_ segments: [RenderSegment], at date: Date) -> Text {
        segments.reduce(Text("")) { text, segment in
            switch segment {
            case .text(let value, _):
                return Text("\(text)\(value)")
            case .sticker(let sticker):
                if let frame = animations[sticker.code]?.frame(at: date, reducingMotion: reduceMotion) {
                    let image = Image(decorative: frame, scale: CGFloat(frame.height) / stickerSize)
                    return Text("\(text)\(Text(image).accessibilityLabel("论坛表情 \(sticker.code)"))")
                }
                return Text("\(text)\(Text(":\(sticker.code):"))")
            }
        }
    }
}
