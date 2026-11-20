import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct ProfileView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @Environment(\.openMemberDestination) private var openMember
    @State private var loader = ResourceLoader<AccountProfile>()
    @State private var showsSignIn = false
    @State private var isConfirmingFollow = false

    private var isOwnProfile: Bool { account.user?.id == userID }
    private var profileURL: URL { NodeSeekRoute.origin.appending(path: "space/\(userID)") }

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { profile in
            List {
                Section {
                    ProfileIdentityHeader(profile: profile)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    if !isOwnProfile {
                        HStack(spacing: 12) {
                            Button { openMember(.conversation(profile.recipient)) } label: {
                                Label("私聊", image: .inkWriteMail)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.seekPill)
                            if let followed = profile.followed {
                                Button { Task { await changeFollow(followed) } } label: {
                                    Label(followed ? "已关注" : "关注", image: followed ? .inkFollowing : .inkFollowMember)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                                .buttonStyle(.seekPill(primary: false)).disabled(loader.updating || loader.loading || isConfirmingFollow)
                            }
                        }.padding(.bottom, 8).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                }
                Section("社区记录") {
                    NavigationLink(value: MemberDestination.posts(.topics, userID: userID)) {
                        LabeledContent("主题", value: profile.topics.map { $0.formatted() } ?? "—")
                    }
                    NavigationLink(value: MemberDestination.posts(.replies, userID: userID)) {
                        LabeledContent("回复", value: profile.replies.map { $0.formatted() } ?? "—")
                    }
                    if isOwnProfile {
                        NavigationLink { ConnectionsView(follows:true,userID:userID) } label: { LabeledContent("关注",value:profile.follows.map { $0.formatted() } ?? "—") }
                        NavigationLink { ConnectionsView(follows:false,userID:userID) } label: { LabeledContent("粉丝",value:profile.fans.map { $0.formatted() } ?? "—") }
                    } else {
                        LabeledContent("关注", value: profile.follows.map { $0.formatted() } ?? "—")
                        LabeledContent("粉丝", value: profile.fans.map { $0.formatted() } ?? "—")
                        if let owner = account.user { NavigationLink(value: AppDestination.stardustTransfer(userID: owner.id, recipient: profile.recipient)) { Label("转账星尘",image: .inkTransferDust) } }
                    }
                    if let coins = profile.coins { LabeledContent("鸡腿", value: coins.formatted()) }
                    if let stardust = profile.stardust { LabeledContent("星尘", value: stardust.formatted()) }
                }
                Section("个人介绍") {
                    if let readme = profile.readme, !readme.isEmpty { ForumMarkdown(markdown: readme).padding(.vertical, 10) }
                    else { Text("还没有填写个人介绍").foregroundStyle(.secondary) }
                }
                if isOwnProfile, let signature = profile.signature, !signature.isEmpty { Section("签名") { ForumMarkdown(markdown: signature) } }
            }
        }
        .seekGroupedList().navigationTitle(isOwnProfile ? "我的主页" : "个人主页")
        .toolbar {
            if isOwnProfile {
                NavigationLink(value: MemberDestination.editProfile) { Label("编辑资料", image: .inkEditProfile) }
            }
            ShareLink(item: profileURL) { Label("分享个人主页", image: .inkShareProfile) }
        }
        .task(id: "\(userID)|\(account.revision)") { await load() }
        .refreshable { await load(force: true) }
        .sheet(isPresented: $showsSignIn) { SignInView() }
    }

    private func load(force: Bool = false) async {
        if isOwnProfile { await loader.load(account.website, .editableProfile(userID), userID: userID, force: force) }
        else { await loader.loadPublic(account.website, .profile(userID), viewerID: account.user?.id, force: force) }
    }
    private func changeFollow(_ followed: Bool) async {
        guard !isConfirmingFollow else { return }
        isConfirmingFollow = true
        defer { isConfirmingFollow = false }
        do {
            try await account.withConfirmedSignIn(onSignedOut: { showsSignIn = true }) { viewer in
                guard viewer.id != userID else { return }
                if await loader.action(account.website, .follow(memberID: userID, followed: followed), userID: viewer.id) != nil {
                    await load(force: true)
                    await account.refresh(force: true)
                }
            }
        } catch is CancellationError {
        } catch {
            loader.error = LoadFailure(error)
        }
    }
}
