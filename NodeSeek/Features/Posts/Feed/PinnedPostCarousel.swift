import NodeSeekCore
import SwiftUI

// A UI test tap can land seconds after it located a card on a slow runner, by when autoplay has moved on.
#if DEBUG
private let carouselAutoplayIsOffForUITests = ProcessInfo.processInfo.arguments.contains("--ui-test-no-carousel-autoplay")
#else
private let carouselAutoplayIsOffForUITests = false
#endif

struct PinnedPostCarousel<Card: View>: View {
    private enum PageID: Hashable, Sendable {
        case post(Int)
        case beforeFirst(Int)
        case afterLast(Int)

        var postID: Int {
            switch self {
            case .post(let id), .beforeFirst(let id), .afterLast(let id): id
            }
        }

        var isCopy: Bool { self != .post(postID) }
    }

    private struct Page: Identifiable {
        let id: PageID
        let post: PostSummary
    }

    private struct Countdown: Equatable {
        let postID: Int
        let restart: Int
    }

    let posts: [PostSummary]
    let card: (PostSummary) -> Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.postTransitionNamespace) private var postTransitionNamespace
    @Environment(\.scenePhase) private var scenePhase
    @State private var position = ScrollPosition(idType: PageID.self)
    @State private var settledID: Int?
    @State private var hasPositionedFirstPage = false
    @State private var isVisible = false
    @State private var scrollStartedAt: ContinuousClock.Instant?
    @State private var restart = 0
    @State private var deadline: ContinuousClock.Instant?
    @State private var outgoingFill: (postID: Int, fraction: CGFloat)?

    private var pages: [Page] {
        let originals = posts.map { Page(id: .post($0.id), post: $0) }
        guard posts.count > 1, let first = posts.first, let last = posts.last else { return originals }
        return [Page(id: .beforeFirst(last.id), post: last)]
            + originals + [Page(id: .afterLast(first.id), post: first)]
    }

    private static var pageDuration: Duration { .seconds(6) }
    private static var cardSpacing: CGFloat { 16 }
    private var currentID: Int? { settledID ?? posts.first?.id }
    private var allowsAutoplay: Bool { !reduceMotion && !voiceOverEnabled && !carouselAutoplayIsOffForUITests }
    private var countdown: Countdown? {
        guard hasPositionedFirstPage, isVisible, scrollStartedAt == nil, scenePhase == .active, allowsAutoplay,
              posts.count > 1, let currentID else { return nil }
        return Countdown(postID: currentID, restart: restart)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Self.cardSpacing) {
                    ForEach(pages) { page in
                        card(page.post)
                            .environment(\.postTransitionNamespace, page.id.isCopy ? nil : postTransitionNamespace)
                            .accessibilityHidden(page.id.isCopy)
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(page.id)
                    }
                }
                // Every card takes the tallest card's height, so swiping never changes the carousel's height.
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            // The feed's readable-width margins would otherwise reach this nested scroll view too.
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .safeAreaPadding(.horizontal, 16)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne, anchor: .center))
            .scrollPosition($position, anchor: .center)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { $0.contentSize.width > 0 } action: { _, hasContent in
                if hasContent, !hasPositionedFirstPage, let firstID = posts.first?.id {
                    hasPositionedFirstPage = true
                    settledID = firstID
                    moveWithoutAnimation(to: .post(firstID))
                }
            }
            .onScrollPhaseChange { _, phase, context in
                if phase == .idle {
                    finishScroll(at: context.geometry)
                } else if scrollStartedAt == nil {
                    scrollStartedAt = .now
                }
            }

            HStack(spacing: 0) {
                ForEach(posts) { post in
                    let isCurrent = post.id == currentID
                    Button {
                        if isCurrent {
                            deadline = nil
                            restart += 1
                        } else {
                            show(pageForIndicator(post.id))
                        }
                    } label: {
                        indicator(for: post.id, isCurrent: isCurrent)
                            .frame(width: 24, height: 24)
                            .background(.clear)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(post.title)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
            .transaction { $0.animation = nil }
            // Match the top inset of the next list card below the indicators.
            .padding(.top, PostRow.listVerticalInset)
        }
        .onScrollVisibilityChange { isVisible = $0 }
        .onChange(of: posts.map(\.id)) { _, ids in
            if let settledID, !ids.contains(settledID), let firstID = ids.first {
                self.settledID = firstID
                deadline = nil
                moveWithoutAnimation(to: .post(firstID))
            }
        }
        .task(id: countdown) { [countdown] in
            guard let countdown else {
                if scrollStartedAt == nil || !isVisible || scenePhase != .active {
                    deadline = nil
                }
                return
            }
            let end = ContinuousClock.now + Self.pageDuration
            deadline = end
            do { try await Task.sleep(until: end, clock: .continuous) } catch { return }
            guard !Task.isCancelled, countdown == self.countdown,
                  let index = posts.firstIndex(where: { $0.id == countdown.postID }) else { return }
            if index < posts.count - 1 {
                show(.post(posts[index + 1].id))
            } else if let first = posts.first {
                show(.afterLast(first.id))
            }
        }
    }

    private func pageForIndicator(_ postID: Int) -> PageID {
        if postID == posts.first?.id, currentID == posts.last?.id {
            return .afterLast(postID)
        }
        if postID == posts.last?.id, currentID == posts.first?.id {
            return .beforeFirst(postID)
        }
        return .post(postID)
    }

    private func finishScroll(at geometry: ScrollGeometry) {
        let pages = self.pages
        guard !pages.isEmpty, geometry.contentSize.width > 0 else {
            scrollStartedAt = nil
            return
        }
        let step = (geometry.contentSize.width + Self.cardSpacing) / CGFloat(pages.count)
        // The position binding can still point to the previous card when scrolling becomes idle.
        let center = layoutDirection == .rightToLeft
            ? geometry.contentSize.width - geometry.visibleRect.midX
            : geometry.visibleRect.midX
        let index = min(max(Int((center + Self.cardSpacing / 2) / step), 0), pages.count - 1)
        let page = pages[index].id
        if let currentID, currentID != page.postID {
            outgoingFill = (currentID, fillFraction)
        }
        settledID = page.postID
        deadline = nil
        scrollStartedAt = nil
        if page.isCopy {
            // The two cards look identical, so moving to the original stays invisible.
            moveWithoutAnimation(to: .post(page.postID))
        }
    }

    private func moveWithoutAnimation(to page: PageID) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(id: page, anchor: .center)
        }
    }

    private func show(_ page: PageID) {
        if reduceMotion {
            settledID = page.postID
            moveWithoutAnimation(to: .post(page.postID))
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                position.scrollTo(id: page, anchor: .center)
            }
        }
    }

    private var fillFraction: CGFloat {
        guard let deadline else { return 0 }
        let remaining = (scrollStartedAt ?? .now).duration(to: deadline)
        return CGFloat(min(1, max(0, 1 - remaining / Self.pageDuration)))
    }

    private func indicator(for postID: Int, isCurrent: Bool) -> some View {
        Capsule()
            .fill(isCurrent && !allowsAutoplay ? Color.seekInk : Color.secondary.opacity(0.35))
            .frame(width: isCurrent ? 16 : 5, height: 5)
            .overlay {
                if allowsAutoplay, isVisible, isCurrent || outgoingFill?.postID == postID {
                    TimelineView(.animation(paused: !isCurrent || scrollStartedAt != nil || deadline == nil)) { _ in
                        let fraction = isCurrent ? fillFraction : (outgoingFill?.fraction ?? 0)
                        Rectangle()
                            .fill(Color.seekInk)
                            .frame(width: 16, height: 5)
                            .scaleEffect(x: fraction, y: 1, anchor: .leading)
                            .transaction { $0.animation = nil }
                    }
                    .opacity(isCurrent ? 1 : 0)
                }
            }
            .clipShape(.capsule)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isCurrent)
    }
}
