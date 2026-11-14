import SwiftUI

struct TextWithTrailingLabel: View {
    let text: Text
    let label: Text?
    var hasLinks = false
    @State private var lastLineWidth: CGFloat?

    @ViewBuilder private var bodyText: some View {
        // Selectable SwiftUI text can consume taps intended for inline links.
        if hasLinks { text }
        else { text.textSelection(.enabled) }
    }

    var body: some View {
        if let label {
            TrailingLabelLayout(lastLineWidth: lastLineWidth) {
                bodyText
                    .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                        let width = layouts.first?.layout.last.flatMap { line in
                            line.contains { $0.layoutDirection == .rightToLeft } ? nil : line.typographicBounds.width
                        }
                        Color.clear.onChange(of: width, initial: true) { _, width in
                            lastLineWidth = width
                        }
                    }
                label
            }
        } else {
            bodyText
        }
    }
}

private struct TrailingLabelLayout: Layout {
    let lastLineWidth: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(proposal, subviews: subviews)
        let widthProposal = ProposedViewSize(width: proposal.width, height: nil)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: widthProposal)
        subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.minY + layout.labelTop),
                          anchor: .topTrailing, proposal: widthProposal)
    }

    private func arrangement(_ proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, labelTop: CGFloat) {
        let widthProposal = ProposedViewSize(width: proposal.width, height: nil)
        let text = subviews[0].dimensions(in: widthProposal)
        let label = subviews[1].dimensions(in: widthProposal)
        let textBaseline = text[.lastTextBaseline]
        let isSingleLine = text[.firstTextBaseline] == textBaseline
        let lineWidth = isSingleLine ? text.width : (lastLineWidth ?? .infinity)
        // Keep the body wrapped at its original width and grow the bubble only if the label fits.
        let inlineWidth = max(text.width, lineWidth + 8 + label.width)

        if inlineWidth <= (proposal.width ?? .infinity), inlineWidth.isFinite {
            let labelTop = max(0, textBaseline - label[.lastTextBaseline])
            return (CGSize(width: inlineWidth, height: max(text.height, labelTop + label.height)), labelTop)
        }

        let labelTop = text.height + 2
        return (CGSize(width: max(text.width, label.width), height: labelTop + label.height), labelTop)
    }
}
