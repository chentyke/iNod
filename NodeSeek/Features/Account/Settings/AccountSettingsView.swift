import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct AccountSettingsView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @AppStorage("showsBlockedContent") private var showsBlocked = false
    @State private var confirmsSignOut = false
    @State private var showsError = false
    @State private var error = ""

    private var websitePreferencesSubtitle: String {
        account.user?.canCustomizeStyle == true
            ? "节日装饰与网页自定义 CSS"
            : "管理官网网页的节日装饰"
    }

    var body: some View {
        List {
            if let user = account.user {
                Section {
                    NavigationLink(value: AccountDestination.profile) {
                        AccountSettingsIdentityCard(user: user)
                    }
                    .listRowInsets(AccountSettingsMetrics.accountCardInsets)
                    .listRowBackground(Color.seekCard)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                NavigationLink(value: MemberDestination.editProfile) {
                    SettingsRowContent(
                        title: "个人资料",
                        subtitle: "一句话介绍、签名与主页介绍",
                        symbol: "person.text.rectangle"
                    )
                }
                .accessibilityIdentifier("settings-row-profile")
                .settingsRowStyle()

                NavigationLink {
                    AvatarEditorView(userID: userID)
                } label: {
                    SettingsRowContent(
                        title: "修改头像",
                        subtitle: "裁切正方形头像并同步到官网",
                        symbol: "photo.circle"
                    )
                }
                .accessibilityIdentifier("settings-row-avatar")
                .settingsRowStyle()

                NavigationLink {
                    AccountSecurityView(userID: userID)
                } label: {
                    SettingsRowContent(
                        title: "登录与安全",
                        subtitle: "密码、双因素验证、Telegram 与登录记录",
                        symbol: "lock.shield"
                    )
                }
                .accessibilityIdentifier("settings-row-security")
                .settingsRowStyle()
            } header: {
                SeekSectionTitle(title: "资料与安全")
            }

            Section {
                NavigationLink {
                    HomepageSettingsView(userID: userID)
                } label: {
                    SettingsRowContent(
                        title: "首页版块",
                        subtitle: "选择在社区首页显示的分类",
                        symbol: "rectangle.grid.1x2"
                    )
                }
                .accessibilityIdentifier("settings-row-homepage")
                .settingsRowStyle()

                NavigationLink {
                    BlockedMembersView(userID: userID)
                } label: {
                    SettingsRowContent(
                        title: "屏蔽用户",
                        subtitle: "管理已屏蔽的用户名单",
                        symbol: "person.slash"
                    )
                }
                .accessibilityIdentifier("settings-row-blocks")
                .settingsRowStyle()

                Toggle(isOn: $showsBlocked) {
                    SettingsRowContent(
                        title: "显示被屏蔽的内容",
                        subtitle: "开启后在列表与帖子中保留被屏蔽用户的发言",
                        symbol: "eye"
                    )
                }
                .tint(Color.seekGreen)
                .accessibilityIdentifier("settings-toggle-shows-blocked")
                .settingsRowStyle(alignSeparator: false)
            } header: {
                SeekSectionTitle(title: "内容与屏蔽")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                        SeekIconTile(symbol: "circle.lefthalf.filled")
                        VStack(alignment: .leading, spacing: AccountSettingsMetrics.rowLineSpacing) {
                            Text("显示模式")
                                .foregroundStyle(Color.seekInk)
                            Text("仅作用于 iNod 客户端界面")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    SeekSegmentedPicker(
                        title: "显示模式",
                        selection: $appearance,
                        options: AppAppearance.allCases,
                        label: \.title
                    )
                    .accessibilityIdentifier("settings-appearance-picker")
                }
                .padding(.vertical, 2)
                .settingsRowStyle(alignSeparator: false)

                NavigationLink {
                    WebsitePreferencesView(userID: userID)
                } label: {
                    SettingsRowContent(
                        title: "官网显示设置",
                        subtitle: websitePreferencesSubtitle,
                        symbol: "globe"
                    )
                }
                .accessibilityIdentifier("settings-row-website-preferences")
                .settingsRowStyle(alignSeparator: false)
            } header: {
                SeekSectionTitle(title: "外观与显示")
            }

            Section {
                Button(role: .destructive) {
                    confirmsSignOut = true
                } label: {
                    HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                        SeekIconTile(symbol: "rectangle.portrait.and.arrow.right", tint: .red)
                        Text(account.isSigningOut ? "正在退出…" : "退出登录")
                            .foregroundStyle(.red)
                        Spacer(minLength: 8)
                        if account.isSigningOut {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.seekRow)
                .disabled(account.isSigningOut)
                .accessibilityIdentifier("settings-sign-out-button")
                .settingsRowStyle(alignSeparator: false)
            }
        }
        .seekGroupedList()
        .contentMargins(.top, 12, for: .scrollContent)
        .navigationTitle("账号设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("退出登录？", isPresented: $confirmsSignOut) {
            Button("退出登录", role: .destructive) { Task { await signOut() } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("本机保存的发帖与私信草稿会保留。")
        }
        .alert("未能退出", isPresented: $showsError) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(error)
        }
    }

    private func signOut() async {
        do {
            try await account.signOut()
        } catch {
            self.error = SiteError.displayMessage(for: error)
            showsError = true
        }
    }
}

private struct AccountSettingsIdentityCard: View {
    let user: SignedInUser
    @Environment(\.dynamicTypeSize) private var typeSize

    private var metadataText: String {
        var parts = ["UID \(String(user.id))"]
        if let level = user.level {
            parts.append("Lv \(level)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    AvatarView(name: user.name, url: user.avatarURL, size: AccountSettingsMetrics.accountAvatarSize)
                    summaryLabels
                }
            } else {
                HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                    AvatarView(name: user.name, url: user.avatarURL, size: AccountSettingsMetrics.accountAvatarSize)
                    summaryLabels
                    Spacer(minLength: 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account-settings-identity-card")
        .accessibilityLabel("\(user.name)，\(metadataText)，查看我的主页")
    }

    private var summaryLabels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.name)
                .font(.headline)
                .foregroundStyle(Color.seekInk)
            Text(metadataText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
