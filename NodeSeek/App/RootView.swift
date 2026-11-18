import NodeSeekClient
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.displayScale) private var displayScale
    @State private var tabAvatar: (url: URL, image: UIImage)?

    private var usesSidebarAdaptableTabs: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    var body: some View {
        let avatarURL = account.user.map { account.versionedAvatarURL($0.avatarURL) }
        let tabs = TabView {
            Tab {
                CommunityRootView()
                    #if DEBUG && !targetEnvironment(macCatalyst)
                    .background {
                        if UIDevice.current.userInterfaceIdiom == .pad,
                           ProcessInfo.processInfo.arguments.contains("--ui-test-open-sidebar") {
                            UITestSidebarOpener()
                        }
                    }
                    #endif
            } label: {
                tabLabel("社区", icon: Image(systemName: "bubble.left.and.bubble.right"))
            }
            .accessibilityLabel("社区")
            Tab {
                ForumNavigationStack { NotificationsView().id(account.revision) }
            } label: {
                tabLabel("通知", icon: Image(systemName: "bell"))
            }
            .accessibilityLabel("通知")
            .badge(account.inbox.unreadCount)
            Tab {
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
            return Image(systemName: "person.crop.circle")
        }
        return Image(uiImage: tabAvatar.image)
    }

    private func loadTabAvatar(from url: URL?) async {
        tabAvatar = nil
        guard let url,
              let avatar = try? await AvatarImageLoader.shared.load(url),
              !Task.isCancelled else { return }

        // The system tab bar takes an image, so draw the circular crop and ring into it.
        let renderer = ImageRenderer(content:
            Image(decorative: avatar, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(.circle)
                .overlay { Circle().strokeBorder(.black, lineWidth: 0.5) }
        )
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
