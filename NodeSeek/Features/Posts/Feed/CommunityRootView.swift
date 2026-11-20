import NodeSeekClient
import NodeSeekCore
import SwiftUI
import UIKit

/// The community feed and its reader share the same selection across display sizes.
struct CommunityRootView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.tabBarPlacement) private var tabPlacement
    let sharedTabRow: ReaderTabRow?
    @Binding var showsTopTabs: Bool
    @State private var selectedPost: PostSummary?
    @State private var detailPath = NavigationPath()
    @State private var compactPath = NavigationPath()
    @State private var hasHinge = false
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    private var usesTabletLayout: Bool {
        #if targetEnvironment(macCatalyst)
        // Like Mail: list and reader side by side, so opening a post never covers the list.
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    var body: some View {
        community
            .onChange(of: account.user?.id) { previous, current in
                if previous != nil, previous != current {
                    select(nil)
                    compactPath = NavigationPath()
                }
            }
    }

    @ViewBuilder private var community: some View {
        if usesTabletLayout {
            GeometryReader { proxy in
                let usesSplit = SeekLayout.usesFeedSplit(
                    forWidth: proxy.size.width,
                    supportsSplit: true,
                    isCompact: horizontalSizeClass == .compact
                )
                Group {
                    if usesSplit {
                        splitLayout(totalWidth: proxy.size.width)
                    } else {
                        compactLayout
                    }
                }
                .onChange(of: usesSplit) { _, isSplit in
                    syncPresentationMode(isSplit: isSplit)
                }
                .onChange(of: compactPath.isEmpty) { _, isEmpty in
                    if isEmpty && !usesSplit {
                        selectedPost = nil
                    }
                }
            }
            .onChange(of: tabPlacement == .topBar, initial: true) { _, visible in showsTopTabs = visible }
        } else if #available(iOS 27.1, *) {
            Group {
                if hasHinge {
                    NavigationSplitView(preferredCompactColumn: $compactColumn) {
                        splitFeed
                    } detail: {
                        splitReader
                    }
                    .navigationSplitViewStyle(.balanced)
                    .onChange(of: detailPath.isEmpty) { _, isEmpty in
                        if isEmpty, selectedPost == nil { compactColumn = .sidebar }
                    }
                    .environment(\.keepsTabBarVisible, horizontalSizeClass == .regular)
                } else {
                    compactLayout
                }
            }
            // Keep the native split view mounted on both displays so its navigation survives folding.
            .onHingeChange(isEnabled: !hasHinge) { _, context in
                if context.hinge != nil { hasHinge = true }
            }
        } else {
            compactLayout
        }
    }

    private func splitLayout(totalWidth: CGFloat) -> some View {
        let feedWidth = SeekLayout.feedPaneWidth(forTotalWidth: totalWidth)
        return HStack(spacing: 0) {
            splitFeed
                .safeAreaPadding(.top, sharedTabRow?.topInset ?? 0)
                .ignoresSafeArea(.container, edges: sharedTabRow == nil ? [] : .top)
                .frame(width: feedWidth)
                // Keep the list above the reader background near the iPad tab bar.
                .zIndex(sharedTabRow == nil ? 0 : 1)

            Rectangle()
                .fill(Color.seekHairline.opacity(0.65))
                .frame(width: SeekLayout.splitDividerWidth)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)

            splitReader
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SeekCanvas())
        .environment(\.keepsTabBarVisible, true)
        .toolbarVisibility(.visible, for: .tabBar)
    }

    private var splitFeed: some View {
        FeedView(selectedPostID: selectedPost?.id)
            .tint(Color.seekGreen)
            .environment(\.openPost, PostNavigationAction { select($0) })
            .environment(\.openMemberDestination, MemberNavigationAction { push($0) })
            .environment(\.openAccountPost, AccountPostNavigationAction { push($0) })
            .environment(\.openAccountDestination, AccountNavigationAction { push($0) })
            .environment(\.openURL, detailOpenURLAction)
    }

    private var splitReader: some View {
        ForumNavigationStack(path: $detailPath) {
            if let post = selectedPost {
                ThreadView(post: post, presentation: .splitDetail, sharedTabRow: sharedTabRow,
                           onClose: { select(nil) })
                    .id(post.id)
            } else {
                FeedDetailPlaceholder()
            }
        }
        .environment(\.suppressesCanvasGlow, true)
    }

    private func select(_ post: PostSummary?) {
        selectedPost = post
        detailPath = NavigationPath()
        compactColumn = post == nil ? .sidebar : .detail
    }

    private func push(_ destination: some Hashable) {
        detailPath.append(destination)
        compactColumn = .detail
    }

    private var compactLayout: some View {
        ForumNavigationStack(
            path: $compactPath,
            restoresTabBarDuringZoom: true,
            onOpenRootPost: { selectedPost = $0 }
        ) {
            FeedView()
        }
    }

    private func syncPresentationMode(isSplit: Bool) {
        if isSplit {
            compactPath = NavigationPath()
        } else {
            detailPath = NavigationPath()
            if let post = selectedPost, compactPath.isEmpty {
                var path = NavigationPath()
                path.append(post)
                compactPath = path
            }
        }
    }

    private var detailOpenURLAction: OpenURLAction {
        OpenURLAction { url in
            switch ForumLink.parse(url.absoluteString) {
            case .native(.post(let address)) where address.page <= 1 && address.floor == nil:
                select(address.summary)
                return .handled
            case .native(let destination):
                push(destination)
                return .handled
            case .website(let url):
                return .systemAction(url)
            case nil:
                return .systemAction
            }
        }
    }
}

private struct FeedDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(.inkReadPost)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("选择帖子开始阅读")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("feed-detail-placeholder")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeekCanvas())
        .toolbar(.hidden, for: .navigationBar)
    }
}
