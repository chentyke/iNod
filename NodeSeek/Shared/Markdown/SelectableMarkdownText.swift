import NodeSeekCore
import SwiftUI
import UIKit

struct SelectableMarkdownText: UIViewRepresentable {
    struct Paragraph: Equatable {
        let markdown: String
        let isHeading: Bool

        init?(_ block: MarkdownBlock) {
            switch block {
            case .text(let text): (markdown, isHeading) = (text, false)
            case .heading(let text): (markdown, isHeading) = (text, true)
            default: return nil
            }
            guard InlineContent.parse(markdown) == [.text(markdown)] else { return nil }
        }
    }

    let paragraphs: [Paragraph]
    let spacing: CGFloat
    @Environment(\.forumDocumentURL) private var documentURL
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .body) private var bodySize = 17.0
    @ScaledMetric(relativeTo: .title3) private var headingSize = 20.0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.delegate = context.coordinator
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.linkTextAttributes = [.foregroundColor: UIColor(Color.seekGreen)]
        view.accessibilityIdentifier = "post-selectable-text"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.openURL = openURL
        let input = RenderInput(paragraphs: paragraphs, documentURL: documentURL, spacing: spacing,
                                bodySize: bodySize, headingSize: headingSize)
        guard context.coordinator.input != input else { return }
        context.coordinator.input = input
        view.attributedText = input.attributedText()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        fileprivate var input: RenderInput?
        var openURL: OpenURLAction?

        func textView(_ textView: UITextView, primaryActionFor item: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = item.content, let openURL else { return defaultAction }
            return UIAction { _ in openURL(url) }
        }
    }

    fileprivate struct RenderInput: Equatable {
        let paragraphs: [Paragraph]
        let documentURL: URL
        let spacing: CGFloat
        let bodySize: CGFloat
        let headingSize: CGFloat

        func attributedText() -> NSAttributedString {
            let result = NSMutableAttributedString()
            for (index, paragraph) in paragraphs.enumerated() {
                let source = ForumText.attributed(paragraph.markdown, baseURL: documentURL)
                let style = NSMutableParagraphStyle()
                style.lineSpacing = paragraph.isHeading ? 0 : 5
                let text = NSMutableAttributedString()
                for run in source.runs {
                    let intent = run.inlinePresentationIntent ?? []
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: font(for: intent, heading: paragraph.isHeading),
                        .foregroundColor: UIColor.label,
                        .paragraphStyle: style
                    ]
                    if let link = run.link { attributes[.link] = link }
                    if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    text.append(NSAttributedString(string: String(source[run.range].characters), attributes: attributes))
                }
                if index < paragraphs.count - 1, text.length > 0 {
                    let lastCharacter = NSRange(location: text.length - 1, length: 1)
                    let lastLine = (text.string as NSString).paragraphRange(for: lastCharacter)
                    let trailingStyle = NSMutableParagraphStyle()
                    trailingStyle.lineSpacing = style.lineSpacing
                    trailingStyle.paragraphSpacing = spacing
                    text.append(NSAttributedString(string: "\n", attributes: [
                        .font: font(for: [], heading: paragraph.isHeading)
                    ]))
                    text.addAttribute(.paragraphStyle, value: trailingStyle,
                                      range: NSRange(location: lastLine.location, length: lastLine.length + 1))
                }
                result.append(text)
            }
            return result
        }

        private func font(for intent: InlinePresentationIntent, heading: Bool) -> UIFont {
            let size = heading ? headingSize : bodySize
            let bold = heading || intent.contains(.stronglyEmphasized)
            let weight: UIFont.Weight = bold ? .bold : .regular
            let base = intent.contains(.code) ? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
                                              : UIFont.systemFont(ofSize: size, weight: weight)
            guard intent.contains(.emphasized),
                  let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.traitItalic))
            else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }
    }
}
