import NodeSeekClient
import NodeSeekCore
import SwiftUI
import UIKit

/// Root of the community tab: side-by-side feed and thread panes on wide iPad and Mac windows,
/// falling back to a single zoom-push stack on iPhone and narrow windows.
struct CommunityRootView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.tabBarPlacement) private var tabPlacement
    let sharedTabRow: ReaderTabRow?
    @Binding var showsTopTabs: Bool
    @State private var selectedPost: PostSummary?
    @State private var detailPath = NavigationPath()
    @State private var compactPath = NavigationPath()

    private var supportsSplit: Bool {
        #if targetEnvironment(macCatalyst)
        // Like Mail: list and reader side by side, so opening a post never covers the list.
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    var body: some View {
        if supportsSplit {
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
            .onChange(of: account.user?.id) { previous, current in
                if previous != nil, previous != current {
                    selectedPost = nil
                    detailPath = NavigationPath()
                    compactPath = NavigationPath()
                }
            }
        } else {
            ForumNavigationStack(restoresTabBarDuringZoom: true) {
                FeedView()
            }
        }
    }

    private func splitLayout(totalWidth: CGFloat) -> some View {
        let feedWidth = SeekLayout.feedPaneWidth(forTotalWidth: totalWidth)
        return HStack(spacing: 0) {
            FeedView(selectedPostID: selectedPost?.id)
                .safeAreaPadding(.top, sharedTabRow?.topInset ?? 0)
                .ignoresSafeArea(.container, edges: sharedTabRow == nil ? [] : .top)
                .frame(width: feedWidth)
                // The reader background can extend under the list when its edge meets the tab bar inset.
                .zIndex(sharedTabRow == nil ? 0 : 1)
                .tint(Color.seekGreen)
                .environment(\.openPost, PostNavigationAction { post in
                    selectedPost = post
                    detailPath = NavigationPath()
                })
                .environment(\.openMemberDestination, MemberNavigationAction { destination in
                    detailPath.append(destination)
                })
                .environment(\.openAccountPost, AccountPostNavigationAction { post in
                    detailPath.append(post)
                })
                .environment(\.openAccountDestination, AccountNavigationAction { destination in
                    detailPath.append(destination)
                })
                .environment(\.openURL, detailOpenURLAction)

            Rectangle()
                .fill(Color.seekHairline.opacity(0.65))
                .frame(width: SeekLayout.splitDividerWidth)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)

            ForumNavigationStack(path: $detailPath) {
                if let post = selectedPost {
                    ThreadView(
                        post: post,
                        presentation: .splitDetail,
                        sharedTabRow: sharedTabRow,
                        onClose: {
                            selectedPost = nil
                            detailPath = NavigationPath()
                        }
                    )
                    .id(post.id)
                } else {
                    FeedDetailPlaceholder()
                }
            }
            .environment(\.suppressesCanvasGlow, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SeekCanvas())
        .environment(\.keepsTabBarVisible, true)
        .toolbarVisibility(.visible, for: .tabBar)
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
                selectedPost = address.summary
                detailPath = NavigationPath()
                return .handled
            case .native(let destination):
                detailPath.append(destination)
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
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("选择帖子开始阅读")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeekCanvas())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed-detail-placeholder")
    }
}
