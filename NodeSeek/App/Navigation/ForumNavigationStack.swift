import NodeSeekCore
import NodeSeekClient
import SwiftUI

extension EnvironmentValues {
    /// True inside a split detail column whose parent tab must keep its tab bar and sidebar visible.
    @Entry var keepsTabBarVisible = false
}

extension View {
    /// Hides the root tab bar on a full-screen push while leaving an iPad split tab's bar visible.
    func hidesTabBarWhenPushed() -> some View {
        modifier(PushedTabBarVisibility())
    }
}

private struct PushedTabBarVisibility: ViewModifier {
    @Environment(\.keepsTabBarVisible) private var keepsTabBarVisible

    func body(content: Content) -> some View {
        content.toolbarVisibility(keepsTabBarVisible ? .automatic : .hidden, for: .tabBar)
    }
}

struct ForumNavigationStack<Content: View>: View {
    var path: Binding<NavigationPath>? = nil
    var restoresTabBarDuringZoom = false
    var onOpenRootPost: ((PostSummary) -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @Environment(AccountSession.self) private var account
    @Environment(\.keepsTabBarVisible) private var keepsTabBarVisible
    @State private var internalPath = NavigationPath()
    @Namespace private var postTransition

    private var activePath: Binding<NavigationPath> {
        path ?? $internalPath
    }

    var body: some View {
        NavigationStack(path: activePath) {
            content()
                // Restore the root tab bar after a pop, while letting destinations set their own visibility.
                .toolbarVisibility(activePath.wrappedValue.isEmpty ? .visible : .automatic, for: .tabBar)
                .background {
                    if restoresTabBarDuringZoom {
                        FeedTabBarTransition()
                    }
                }
                .memberDestinations()
                .navigationDestination(for: AppDestination.self, destination: destination)
                .navigationDestination(for: AccountDestination.self, destination: accountDestination)
                .navigationDestination(for: PostSummary.self) { post in
                    if keepsTabBarVisible {
                        ThreadView(post: post)
                    } else {
                        ThreadView(post: post, usesZoomTransition: true)
                            .navigationTransition(.zoom(sourceID: post.id, in: postTransition))
                    }
                }
                .navigationDestination(for:AccountPost.self) { ThreadView(post:$0.summary,initialPage:$0.page,initialFloor:$0.floor) }
                .navigationDestination(for:ForumLinkDestination.self) { destination in
                    switch destination {
                    case .post(let address): ThreadView(post:address.summary,initialPage:address.page,initialFloor:address.floor)
                    case .mention(let name): MemberMentionView(name: name)
                    case .member(let id,let section):
                        switch section {
                        case "discussions", "topics": AccountPostsView(kind:.topics,userID:id)
                        case "comments", "replies": AccountPostsView(kind:.replies,userID:id)
                        case "collections" where account.user?.id == id: AccountPostsView(kind:.collections,userID:id)
                        default: ProfileView(userID:id)
                        }
                    case .feed(let category,let sort): FeedView(initialCategory:category,initialSort:sort,isLinkedPage:true)
                    case .search(let query,let category,let sort): FeedView(isSearch:true,initialCategory:category,initialSort:sort,initialQuery:query,isLinkedPage:true)
                    case .recommended: FeedView(recommended:true,isLinkedPage:true)
                    case .lucky(let draw): LuckyView(initial:draw)
                    }
                }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .tint(Color.seekGreen)
        .environment(\.openMemberDestination, MemberNavigationAction { activePath.wrappedValue.append($0) })
        .environment(\.openAccountPost, AccountPostNavigationAction { activePath.wrappedValue.append($0) })
        .environment(\.openPost, PostNavigationAction { post in
            if activePath.wrappedValue.isEmpty { onOpenRootPost?(post) }
            activePath.wrappedValue.append(post)
        })
        .environment(\.postTransitionNamespace, postTransition)
        .environment(\.openAccountDestination, AccountNavigationAction { activePath.wrappedValue.append($0) })
        .environment(\.openURL,OpenURLAction { url in
            switch ForumLink.parse(url.absoluteString) {
            case .native(let destination): activePath.wrappedValue.append(destination); return .handled
            // A page the app has no screen for opens in the reader's browser.
            case .website(let url): return .systemAction(url)
            case nil: return .systemAction
            }
        })
        .onChange(of: account.user?.id) { previous, current in
            if previous != nil, previous != current { activePath.wrappedValue = NavigationPath() }
        }
    }

    @ViewBuilder private func destination(_ value: AppDestination) -> some View {
        switch value {
        case .post(let post, let page, let floor): ThreadView(post: post, initialPage: page, initialFloor: floor)
        case .memberSearch: MemberSearchView()
        case .communityTools: CommunityToolsView()
        case .recommended: FeedView(recommended: true, isLinkedPage: true)
        case .luckyDraw: LuckyView()
        case .networkQuality: NetworkQualityView()
        case .deviceBenchmark: DeviceBenchmarkView()
        case .rulings(let recordID): RulingsView(recordID: recordID) { activePath.wrappedValue.append($0) }
        case .directory(let providers): DirectoryView(providers: providers)
        case .siteArticle(let path, let title): SiteArticleView(path: path, title: title)
        case .connections(let follows, let userID): ConnectionsView(follows: follows, userID: userID)
        case .invitations(let userID): InvitationsView(userID: userID)
        case .imageLibrary(let userID): NodeImageLibraryView(userID: userID)
        case .stardustTransfer(let userID, let recipient): StardustTransferView(userID: userID, recipient: recipient)
        }
    }

    @ViewBuilder private func accountDestination(_ value: AccountDestination) -> some View {
        if let user = account.user {
            switch value {
            case .content(let kind): AccountPostsView(kind: kind, userID: user.id)
            case .ledger(let kind): LedgerView(kind: kind, userID: user.id)
            case .stardustHistory: StardustHistoryView(memberID: user.id)
            case .attendance: AttendanceView(userID: user.id)
            case .progress: AccountProgressView(userID: user.id)
            case .profile: ProfileView(userID: user.id)
            case .settings: AccountSettingsView(userID: user.id)
            }
        } else { ContentUnavailableView("请先登录", systemImage: "person.crop.circle") }
    }
}
