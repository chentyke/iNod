import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct MemberSearchView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.openMemberDestination) private var openMember
    @Environment(\.openAppDestination) private var openAppDestination
    @State private var query = ""
    @State private var submittedUsername: String?
    @State private var loader = ResourceLoader<MemberSearchResponse>()
    @State private var showsSignIn = false
    @State private var showsVerification = false

    private var liveParsed: MemberSearchQuery {
        MemberSearchQuery(query)
    }

    private var searchTaskKey: String {
        "\(submittedUsername ?? "")|\(account.revision)"
    }

    var body: some View {
        List {
            Section {
                CommunitySearchFieldRow(
                    searchIcon: .inkFindMember,
                    prompt: "用户名、UID 或主页链接",
                    text: $query,
                    identifier: "member-search-field",
                    submitButtonIdentifier: "member-search-submit",
                    onSubmit: submitSearch,
                    onClear: clearSearch
                )
                .listRowInsets(CommunityMetrics.searchRowInsets)
                .listRowBackground(Color.seekCard)
                .listRowSeparator(.hidden)
            } header: {
                SeekSectionTitle(title: "输入查找条件")
            } footer: {
                Text("支持输入 @用户名 搜索，也可直接填入数字 UID 或个人主页链接打开主页。")
            }

            if let directID = liveParsed.directMemberID {
                Section {
                    NavigationLink(value: MemberDestination.profile(directID)) {
                        SettingsRowContent(
                            title: "打开 UID \(String(directID)) 的主页",
                            subtitle: "直接访问公开个人资料、主题与回复",
                            symbol: .inkProfile
                        )
                    }
                    .accessibilityIdentifier("member-search-direct-\(String(directID))")
                    .communityRowStyle(alignSeparator: false)
                } header: {
                    SeekSectionTitle(title: "直达主页")
                }
            }

            if let username = submittedUsername {
                resultsSection(for: username)
            }
        }
        .seekGroupedList()
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("查找用户")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: query) { _, current in
            if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                submittedUsername = nil
                loader.value = nil
                loader.error = nil
            }
        }
        .task(id: searchTaskKey) {
            if let username = submittedUsername, !(account.hasLoaded && !account.isLoggedIn) {
                await runSearch(username: username)
            }
        }
        .refreshable {
            if let username = submittedUsername, !(account.hasLoaded && !account.isLoggedIn) {
                await runSearch(username: username, force: true)
            }
        }
        .sheet(isPresented: $showsSignIn) {
            SignInView()
        }
        .sheet(isPresented: $showsVerification, onDismiss: {
            if let username = submittedUsername {
                Task { await runSearch(username: username, force: true) }
            }
        }) {
            WebsiteView(initialURL: NodeSeekRoute.home.url)
        }
    }

    @ViewBuilder
    private func resultsSection(for username: String) -> some View {
        if account.hasLoaded && !account.isLoggedIn {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: CommunityMetrics.rowSpacing) {
                        SeekIconTile(symbol: .inkMemberLogin, tint: .seekGreen)
                        VStack(alignment: .leading, spacing: CommunityMetrics.rowLineSpacing) {
                            Text("按用户名查找需要先登录")
                                .font(.headline)
                                .foregroundStyle(Color.seekInk)
                            Text("登录后可按用户名检索社区成员；若已知对方数字 UID，可在上方直接输入打开主页。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("登录账号", image: .inkSignIn) {
                        showsSignIn = true
                    }
                    .buttonStyle(.seekPill)
                    .accessibilityIdentifier("member-search-sign-in-button")
                }
                .padding(.vertical, 6)
                .listRowInsets(CommunityMetrics.rowInsets)
                .listRowBackground(Color.seekCard)
                .listRowSeparator(.hidden)
            } header: {
                SeekSectionTitle(title: "搜索结果")
            }
        } else {
            Section {
                if let failure = loader.error, loader.value == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(failure.kind == .other ? "未能完成查找" : failure.title)
                            .font(.headline)
                            .foregroundStyle(Color.seekInk)
                        Text(failure.advice)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            SettingsActionPill(
                                title: "重试",
                                symbol: .inkRetrySearch,
                                busyTitle: "查找中…",
                                isBusy: loader.loading,
                                primary: true,
                                fullWidth: false
                            ) {
                                Task { await runSearch(username: username, force: true) }
                            }
                            if failure.kind == .verificationRequired {
                                Button("打开官网验证") {
                                    showsVerification = true
                                }
                                .buttonStyle(.seekPill(primary: false, fullWidth: false, surface: .seekTray))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowInsets(CommunityMetrics.rowInsets)
                    .listRowBackground(Color.seekCard)
                    .listRowSeparator(.hidden)
                } else if loader.loading && loader.value == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在查找「\(username)」…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .listRowInsets(CommunityMetrics.rowInsets)
                    .listRowBackground(Color.seekCard)
                    .listRowSeparator(.hidden)
                } else if let result = loader.value {
                    if let failure = loader.error {
                        LoadFailureBanner(failure: failure, isRetrying: loader.loading) {
                            Task { await runSearch(username: username, force: true) }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    if result.memberList.isEmpty {
                        Text("没有找到与「\(username)」匹配的用户")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .listRowInsets(CommunityMetrics.rowInsets)
                            .listRowBackground(Color.seekCard)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(result.memberList) { member in
                            NavigationLink(value: MemberDestination.profile(member.id)) {
                                SearchedMemberRow(
                                    member: member,
                                    isCurrentUser: member.id == account.user?.id
                                )
                            }
                            .accessibilityIdentifier("searched-member-\(String(member.id))")
                            .communityRowStyle(separatorInset: CommunityMetrics.avatarSeparatorInset)
                            .contextMenu {
                                Button("查看个人主页", image: .inkProfile) {
                                    openMember(.profile(member.id))
                                }
                                if let currentUser = account.user, currentUser.id != member.id {
                                    let recipient = MessageRecipient(id: member.id, name: member.member_name)
                                    Button("发私信", image: .inkWriteMail) {
                                        openMember(.conversation(recipient))
                                    }
                                    Button("转账星尘", image: .inkTransferDust) {
                                        openAppDestination(.stardustTransfer(userID: currentUser.id, recipient: recipient))
                                    }
                                }
                                ShareLink(item: member.spaceURL) { Label("分享个人主页", image: .inkShareProfile) }
                            }
                        }
                    }
                }
            } header: {
                SeekSectionTitle(
                    title: "匹配用户",
                    detail: loader.value.flatMap { $0.memberList.isEmpty ? nil : "\($0.memberList.count) 人" }
                )
            }
        }
    }

    private func submitSearch() {
        let parsed = MemberSearchQuery(query)
        if let username = parsed.usernameQuery {
            if submittedUsername == username {
                Task { await runSearch(username: username, force: true) }
            } else {
                submittedUsername = username
            }
        } else if let directID = parsed.directMemberID {
            openMember(.profile(directID))
        }
    }

    private func clearSearch() {
        query = ""
        submittedUsername = nil
        loader.value = nil
        loader.error = nil
    }

    private func runSearch(username: String, force: Bool = false) async {
        await loader.load(account.website, .memberSearch(username), force: force)
    }
}

private struct SearchedMemberRow: View {
    let member: SearchedMember
    let isCurrentUser: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var avatarURL: URL {
        NodeSeekRoute.origin.appending(path: "avatar/\(member.id).png")
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    AvatarView(name: member.member_name, url: avatarURL, size: CommunityMetrics.avatarSize)
                    detailStack
                }
            } else {
                HStack(alignment: .center, spacing: CommunityMetrics.rowSpacing) {
                    AvatarView(name: member.member_name, url: avatarURL, size: CommunityMetrics.avatarSize)
                    detailStack
                    Spacer(minLength: 8)
                }
            }
        }
        .frame(minHeight: CommunityMetrics.avatarSize)
    }

    private var detailStack: some View {
        VStack(alignment: .leading, spacing: CommunityMetrics.rowLineSpacing) {
            HStack(spacing: 6) {
                Text(member.member_name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.seekInk)
                    .lineLimit(1)
                if isCurrentUser {
                    SettingsStatusPill(text: "我", active: true)
                }
            }

            Text(member.metadataText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            if let bio = member.trimmedBio {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }
        }
    }
}
