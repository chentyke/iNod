import SwiftUI

struct InboxPages: View {
    let userID: Int
    let hasUnreadNotices: Bool
    @Binding var selection: NotificationTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragDistance: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                page(.activity, width: width) {
                    NoticesListView(userID: userID, isSelected: selection == .activity)
                }
                page(.messages, width: width) {
                    MessageThreadsView(userID: userID, isSelected: selection == .messages)
                }
            }
            .contentShape(.rect)
            .clipped()
            .gesture(PageSwipe(direction: swipeDirection, onMove: { distance in
                guard !reduceMotion else { return }
                // Leave room for the unread row's short swipe action before moving the page.
                let rowAllowance = selection == .activity && hasUnreadNotices ? PageSwipe.minimumDistance : 0
                dragDistance = min(max(0, distance - rowAllowance), width)
            }) { completed in
                withAnimation(NotificationTab.animation(reduceMotion: reduceMotion)) {
                    if completed { selection = selection.other }
                    dragDistance = 0
                }
            })
        }
    }

    private var swipeDirection: PageSwipe.Direction {
        (selection == .activity) == (layoutDirection == .leftToRight) ? .left : .right
    }

    private func page<Content: View>(
        _ tab: NotificationTab, width: CGFloat, @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = tab == selection
        let rest = isSelected ? 0 : (tab == .activity ? -width : width)
        let readingDirection: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        let drag = selection == .activity ? -dragDistance : dragDistance
        return content()
            .background(Color.seekCanvas)
            .offset(x: reduceMotion ? 0 : (rest + drag) * readingDirection)
            .opacity(reduceMotion && !isSelected ? 0 : 1)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}
