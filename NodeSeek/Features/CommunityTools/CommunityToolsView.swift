import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct CommunityToolsView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.openAppDestination) private var openDestination
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsSignIn = false

    var body: some View {
        List {
            Section {
                communityFeaturedTiles
                    .listRowInsets(CommunityMetrics.tilesRowInsets)
                    .listRowSeparator(.hidden)

                NavigationLink(value: AppDestination.memberSearch) {
                    SettingsRowContent(
                        title: "查找用户",
                        subtitle: "搜索用户名，或输入 UID 直达主页",
                        symbol: .inkFindMember
                    )
                }
                .accessibilityIdentifier("community-row-member-search")
                .communityRowStyle()

                NavigationLink(value: AppDestination.rulings(recordID: nil)) {
                    SettingsRowContent(
                        title: "管理记录",
                        subtitle: "查看版务处理公示与单条记录详情",
                        symbol: .inkRulings
                    )
                }
                .accessibilityIdentifier("community-row-rulings")
                .communityRowStyle()

                invitationsEntry
                    .listRowInsets(CommunityMetrics.lastCommunityRowInsets)
            } header: {
                SeekSectionTitle(title: "社区")
            }
            .listRowBackground(Color.seekCard)

            Section {
                NavigationLink(value: AppDestination.networkQuality) {
                    SeekRowLabel(title: "网络检测", symbol: .inkNetworkTest)
                }
                NavigationLink(value: AppDestination.deviceBenchmark) {
                    SeekRowLabel(title: "本机性能", symbol: .inkBenchmark)
                }
            } header: {
                SeekSectionTitle(title: "检测")
            }

            Section {
                NavigationLink(value: AppDestination.directory(providers: true)) {
                    SeekRowLabel(title: "合作商家", symbol: .inkMerchant)
                }
                NavigationLink(value: AppDestination.directory(providers: false)) {
                    SeekRowLabel(title: "友情链接", symbol: .inkFriendLink)
                }
                Link(destination: URL(string: "https://rss.nodeseek.com")!) {
                    SeekRowLabel(title: "RSS 订阅", symbol: .inkRss, opensExternally: true)
                }
                Link(destination: URL(string: "https://t.me/nodeseekc")!) {
                    SeekRowLabel(title: "电报频道", symbol: .inkChannel, opensExternally: true)
                }
                Link(destination: URL(string: "https://t.me/nodeseekg")!) {
                    SeekRowLabel(title: "电报群组", symbol: .inkTelegramGroup, opensExternally: true)
                }
            } header: {
                SeekSectionTitle(title: "发现")
            }

            Section {
                NavigationLink(value: AppDestination.siteArticle(path: "about", title: "关于本站")) {
                    SeekRowLabel(title: "关于本站", symbol: .inkSiteAbout)
                }
                NavigationLink(value: AppDestination.siteArticle(path: "termsofservice", title: "隐私协议")) {
                    SeekRowLabel(title: "隐私协议", symbol: .inkPrivacy)
                }
                NavigationLink(value: AppDestination.post(PostAddress("6797")!.summary, page: 1, floor: nil)) {
                    SeekRowLabel(title: "商家申请规则", symbol: .inkMerchantRules)
                }
                NavigationLink(value: AppDestination.post(PostAddress("6800")!.summary, page: 1, floor: nil)) {
                    SeekRowLabel(title: "Premium Provider", symbol: .inkPremiumProvider)
                }
                NavigationLink(value: AppDestination.post(PostAddress("361666")!.summary, page: 1, floor: nil)) {
                    SeekRowLabel(title: "广告合作", symbol: .inkAdvertising)
                }
                Link(destination: URL(string: "https://t.me/nodeseek")!) {
                    SeekRowLabel(title: "联系 NodeSeek", symbol: .inkContactSite, opensExternally: true)
                }
            } header: {
                SeekSectionTitle(title: "NodeSeek")
            }
        }
        .seekGroupedList()
        .contentMargins(.top, 12, for: .scrollContent)
        .navigationTitle("社区工具")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showsSignIn) {
            SignInView()
        }
    }

    private var communityFeaturedTiles: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: CommunityMetrics.stackedTileSpacing))
            : AnyLayout(HStackLayout(spacing: CommunityMetrics.tileSpacing))

        return layout {
            Button {
                openDestination(.recommended)
            } label: {
                CommunityFeatureTile(
                    title: "推荐阅读",
                    subtitle: "社区精选与加精主题",
                    symbol: .inkFeatured,
                    tint: .seekGreen
                )
            }
            .buttonStyle(.seekCard)
            .hoverEffect(.highlight)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("community-tile-recommended")

            Button {
                openDestination(.luckyDraw)
            } label: {
                CommunityFeatureTile(
                    title: "抽奖工具",
                    subtitle: "公开随机数楼层开奖",
                    symbol: .inkDrawPrize,
                    tint: .orange
                )
            }
            .buttonStyle(.seekCard)
            .hoverEffect(.highlight)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("community-tile-lucky")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("community-featured-tiles")
    }

    @ViewBuilder
    private var invitationsEntry: some View {
        if let userID = account.user?.id {
            NavigationLink(value: AppDestination.invitations(userID: userID)) {
                SettingsRowContent(
                    title: "邀请朋友",
                    subtitle: "兑换与分享注册邀请码",
                    symbol: .inkInvite
                )
            }
            .accessibilityIdentifier("community-row-invitations")
        } else {
            Button {
                showsSignIn = true
            } label: {
                SettingsRowContent(
                    title: "邀请朋友",
                    subtitle: "登录后可兑换与管理注册邀请码",
                    symbol: .inkInvite,
                    badge: (text: "需登录", active: false)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.seekRow)
            .accessibilityIdentifier("community-row-invitations")
        }
    }
}
