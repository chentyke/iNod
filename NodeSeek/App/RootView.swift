import NodeSeekClient
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if targetEnvironment(macCatalyst)
    @Environment(MacToolbarModel.self) private var macToolbar: MacToolbarModel?
    #endif
    @State private var tabAvatar: (url: URL, image: UIImage)?
    @State private var selectedTab = RootTab.community
    @State private var showsTopTabs = false

    private var usesSidebarAdaptableTabs: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    var body: some View {
        #if !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .pad {
            GeometryReader { proxy in
                let feedWidth = SeekLayout.feedPaneWidth(forTotalWidth: proxy.size.width)
                let tabRow = horizontalSizeClass == .regular && showsTopTabs && !dynamicTypeSize.isAccessibilitySize
                    ? ReaderTabRow(readerWidth: proxy.size.width - feedWidth - SeekLayout.splitDividerWidth,
                                   topInset: proxy.safeAreaInsets.top)
                    : nil
                tabs(sharedTabRow: tabRow, tabInset: tabRow == nil ? 0 : feedWidth + SeekLayout.splitDividerWidth)
            }
        } else {
            tabs(sharedTabRow: nil)
        }
        #else
        tabs(sharedTabRow: nil)
        #endif
    }

    @ViewBuilder private func tabs(sharedTabRow: ReaderTabRow?, tabInset: CGFloat = 0) -> some View {
        let avatarURL = account.user.map { account.versionedAvatarURL($0.avatarURL) }
        let tabs = TabView(selection: $selectedTab) {
            Tab(value: RootTab.community) {
                CommunityRootView(sharedTabRow: sharedTabRow, showsTopTabs: $showsTopTabs)
                    #if !targetEnvironment(macCatalyst)
                    .ignoresSafeArea(.container, edges: sharedTabRow == nil ? [] : .leading)
                    .background {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            ReaderTabBarInset(amount: selectedTab == .community ? tabInset : 0)
                                .allowsHitTesting(false)
                        }
                    }
                    #endif
                    #if DEBUG && !targetEnvironment(macCatalyst)
                    .background {
                        if UIDevice.current.userInterfaceIdiom == .pad,
                           ProcessInfo.processInfo.arguments.contains("--ui-test-open-sidebar") {
                            UITestSidebarOpener()
                        }
                    }
                    #endif
            } label: {
                tabLabel("社区", icon: Image(.inkCommunity))
            }
            .accessibilityLabel("社区")
            Tab(value: RootTab.notifications) {
                ForumNavigationStack { NotificationsView().id(account.revision) }
            } label: {
                tabLabel("通知", icon: Image(.inkNotices))
            }
            .accessibilityLabel("通知")
            .badge(account.inbox.unreadCount)
            Tab(value: RootTab.account) {
                ForumNavigationStack { AccountView() }.id(account.revision)
            } label: {
                tabLabel("我的", icon: tabIcon(for: avatarURL))
            }
            .accessibilityLabel("我的")
        }
        #if targetEnvironment(macCatalyst)
        .tint(Color.seekSidebarSelection)
        #else
        .tint(Color.seekInk)
        #endif
        .task(id: avatarURL) { await loadTabAvatar(from: avatarURL) }
        #if targetEnvironment(macCatalyst)
        .tabViewSidebarHeader {
            if let macToolbar {
                MacSidebarHeader(model: macToolbar) { selectedTab = .community }
            }
        }
        .onChange(of: macToolbar?.composeRequests) { selectedTab = .community }
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            macToolbar?.tracksSidebar = sizeClass != .compact
        }
        #endif

        if usesSidebarAdaptableTabs {
            tabs.tabViewStyle(.sidebarAdaptable)
        } else {
            tabs
        }
    }

    /// iPhone shows the tabs as icons; iPad and Mac name them so the adaptable sidebar reads clearly.
    @ViewBuilder private func tabLabel(_ title: String, icon: Image) -> some View {
        if usesSidebarAdaptableTabs {
            Label { Text(title) } icon: { icon }
        } else {
            icon
        }
    }

    private func tabIcon(for url: URL?) -> Image {
        guard let tabAvatar, tabAvatar.url == url else {
            return Image(.inkMyAccount)
        }
        return Image(uiImage: tabAvatar.image)
    }

    private func loadTabAvatar(from url: URL?) async {
        tabAvatar = nil
        guard let url,
              let avatar = try? await AvatarImageLoader.shared.load(url),
              !Task.isCancelled else { return }

        // The system tab bar takes an image, so draw the circular crop and ring into it.
        let circle = Image(decorative: avatar, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(.black, lineWidth: 0.5) }
        #if targetEnvironment(macCatalyst)
        // The sidebar reserves a 34-point slot for symbols but uses the bitmap's width for the avatar.
        let renderer = ImageRenderer(content: circle.frame(width: 34))
        #else
        let renderer = ImageRenderer(content: circle)
        #endif
        renderer.scale = displayScale
        if let image = renderer.uiImage {
            tabAvatar = (url, image.withRenderingMode(.alwaysOriginal))
        }
    }
}

#if DEBUG && !targetEnvironment(macCatalyst)
/// Opens iPad's adaptable sidebar on launch when requested by UI tests.
private struct UITestSidebarOpener: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private var didOpen = false

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            openIfNeeded()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            openIfNeeded()
        }

        private func openIfNeeded() {
            guard !didOpen, let tabs = tabBarController else { return }
            didOpen = true
            tabs.sidebar.isHidden = false
        }
    }
}
#endif

private enum RootTab: Hashable {
    case community, notifications, account
}
