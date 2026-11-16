import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct AccountView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.openURL) private var openURL
    @State private var showsWebsite = false
    @State private var showsSignIn = false
    @State private var websiteURL = NodeSeekRoute.home.url

    var body: some View {
        List {
            if let user = account.user {
                Section {
                    Button { openURL(user.spaceURL()) } label: { AccountIdentityHeader(user: user) }
                        .buttonStyle(.seekRow).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    AccountNavigationRow(title: "收藏", symbol: "bookmark", destination: .content(.collections))
                    AccountNavigationRow(title: "我的主题", symbol: "text.bubble", count: user.topicCount, destination: .content(.topics))
                    AccountNavigationRow(title: "我的回复", symbol: "bubble.left", count: user.commentCount, destination: .content(.replies))
                    NavigationLink(value: AppDestination.connections(follows: true, userID: user.id)) { SeekRowLabel(title: "我的关注", symbol: "person.badge.plus") }
                    NavigationLink(value: AppDestination.connections(follows: false, userID: user.id)) { SeekRowLabel(title: "我的粉丝", symbol: "person.2") }
                } header: { SeekSectionTitle(title: "社区记录") }
                Section {
                    AccountBalances(user: user).listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                    AccountNavigationRow(title: "签到", symbol: "calendar.badge.checkmark", destination: .attendance)
                    NavigationLink(value: AccountDestination.progress) { SeekRowLabel(title: "等级与进度", symbol: "chart.bar") }
                } header: { SeekSectionTitle(title: "鸡腿与星尘") }
                .listRowBackground(Color.seekCard)
                Section {
                    NavigationLink(value: AppDestination.imageLibrary(userID: user.id)) {
                        SeekRowLabel(title: "图片上传与管理", symbol: "photo.on.rectangle")
                    }
                    AccountNavigationRow(title: "账号设置", symbol: "gearshape", destination: .settings)
                    NavigationLink(value: AppDestination.invitations(userID: user.id)) { SeekRowLabel(title: "邀请朋友", symbol: "ticket") }
                }
            } else if !account.hasLoaded {
                Section {
                    if account.isRefreshing {
                        HStack { ProgressView(); Text("正在读取登录状态").foregroundStyle(.secondary) }
                    } else {
                        let failure = account.failure
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failure.map { $0.kind == .other ? "暂时无法确认登录状态" : $0.title } ?? "暂时无法确认登录状态")
                                .font(.headline)
                            if let failure {
                                Text(failure.advice).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        Button { Task { await account.refresh(force: true) } } label: {
                            SeekRowLabel(title: "重试", symbol: "arrow.clockwise")
                        }
                    }
                    // Offline, the website can't load either.
                    if account.failure?.kind != .offline {
                        Button { open(NodeSeekRoute.home.url) } label: { SeekRowLabel(title: "打开官网", symbol: "globe", opensExternally: true) }
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "person.crop.circle").font(.largeTitle).foregroundStyle(Color.seekGreen)
                        Text("登录 NodeSeek").font(.title2.bold())
                        Text("登录后可以回复、点赞和投喂鸡腿。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("登录", systemImage: "person.crop.circle") { showsSignIn = true }
                            .buttonStyle(.seekPill)
                    }
                    // The symbol's frame carries a few points of air above its glyph; trim the top to match the button below.
                    .padding(.top, 8).padding(.bottom, 12)
                }
            }
            // Signed in, but the latest check failed: the page still shows what was read before.
            if account.hasLoaded, let error = account.error {
                Section {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("重新读取登录状态", systemImage: "arrow.clockwise") { Task { await account.refresh() } }
                        .disabled(account.isRefreshing)
                }
            }
            Section {
                NavigationLink(value: AppDestination.communityTools) { SeekRowLabel(title: "社区工具", symbol: "square.grid.2x2") }
            }
            Section {
                AccountAboutRow(version: "0.1.0")
                Button { open(NodeSeekRoute.home.url) } label: {
                    SeekRowLabel(title: "NodeSeek 官网", symbol: "globe", opensExternally: true)
                }
            } header: { SeekSectionTitle(title: "关于") }
        }
        .seekGroupedList()
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await account.refresh(force: true) }
        .task { await account.refresh() }
        .sheet(isPresented: $showsWebsite) { WebsiteView(initialURL: websiteURL) }
        .sheet(isPresented: $showsSignIn) { SignInView() }
    }

    private func open(_ url: URL) { websiteURL = url; showsWebsite = true }
}

/// The app's name, what it is, and its version, laid out like the other rows.
private struct AccountAboutRow: View {
    let version: String

    var body: some View {
        HStack(spacing: 12) {
            SeekIconTile(symbol: "info.circle")
            VStack(alignment: .leading, spacing: 2) {
                Text("iNod").foregroundStyle(Color.seekInk)
                Text("非官方 NodeSeek 客户端").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(version).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
