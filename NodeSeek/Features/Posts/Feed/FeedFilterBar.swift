import NodeSeekCore
import SwiftUI

struct FeedFilterBar<Search: View, Actions: View>: View {
    let category: String
    var sort: Binding<FeedSort>?
    let onCategories: () -> Void
    var isSearchExpanded = false
    @ViewBuilder let search: Search
    @ViewBuilder let actions: Actions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if sort == nil {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        CategoryButtonSlot(visibility: isSearchExpanded ? 0 : 1) {
                            categoryButton.padding(.trailing, 10)
                        }
                        // Glass highlights extend beyond the button's layout bounds.
                        .clipShape(.rect.inset(by: -8))
                        .opacity(isSearchExpanded ? 0 : 1)
                        .allowsHitTesting(!isSearchExpanded)
                        .accessibilityHidden(isSearchExpanded)

                        search.glassEffect(.regular.interactive(), in: .capsule)
                    }
                    actions
                }
            } else {
                GlassEffectContainer(spacing: 8) {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { categoryButton; Spacer(); actions }
                            sortPicker.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        HStack(spacing: 10) { categoryButton; sortPicker; actions }
                    }
                }
            }
        }
        .padding(.horizontal, SeekLayout.gutter).padding(.vertical, 8)
        .readableColumn()
    }

    private var categoryButton: some View {
        Button(action: onCategories) {
            HStack(spacing: 6) {
                Text(category)
                Image(.inkChoose).font(.caption.bold()).foregroundStyle(Color.seekButtonIcon)
            }
            .font(.subheadline.bold()).foregroundStyle(Color.seekInk)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .background {
            Color.clear.glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityLabel("选择版块，当前\(category)")
    }

    @ViewBuilder private var sortPicker: some View {
        if let sort {
            FeedSortPicker(selection: sort)
        }
    }
}

private struct CategoryButtonSlot: Layout {
    var visibility: CGFloat

    var animatableData: CGFloat {
        get { visibility }
        set { visibility = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        return CGSize(width: size.width * visibility, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let size = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: CGPoint(x: bounds.maxX - size.width, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(size))
    }
}
