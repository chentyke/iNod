import NodeSeekClient
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.displayScale) private var displayScale
    @State private var tabAvatar: (url: URL, image: UIImage)?

    var body: some View {
        let avatarURL = account.user.map { account.versionedAvatarURL($0.avatarURL) }
        TabView {
            Tab {
                ForumNavigationStack(restoresTabBarDuringZoom: true) { FeedView() }
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
        // A Mac window has no tab bar to show the tabs in, so list them in a sidebar.
        .tabViewStyle(.sidebarAdaptable)
        .tint(Color.seekSidebarSelection)
        #else
        .tint(Color.seekInk)
        #endif
        .task(id: avatarURL) { await loadTabAvatar(from: avatarURL) }
    }

    /// iPhone and iPad show the tabs as icons; the Mac sidebar names them too.
    @ViewBuilder private func tabLabel(_ title: String, icon: Image) -> some View {
        #if targetEnvironment(macCatalyst)
        Label { Text(title) } icon: { icon }
        #else
        icon
        #endif
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
