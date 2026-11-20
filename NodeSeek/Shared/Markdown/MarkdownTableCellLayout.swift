import SwiftUI

struct MarkdownTableCellLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let cell = subviews[0]
        let idealWidth = cell.sizeThatFits(.unspecified).width
        let width = max(76, min(idealWidth, proposal.width ?? 260, 260))
        // Measure the wrapped height even when the grid asks for the ideal size.
        let height = cell.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
