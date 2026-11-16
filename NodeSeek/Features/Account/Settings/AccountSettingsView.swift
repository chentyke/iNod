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

    var body: some View {
        Form {
            Section("账号") {
                NavigationLink(value: MemberDestination.editProfile) { Label("个人资料", systemImage: "person.crop.circle") }
                NavigationLink { AvatarEditorView(userID:userID) } label: { Label("修改头像",systemImage:"photo.circle") }
                NavigationLink { HomepageSettingsView(userID: userID) } label: { Label("首页版块", systemImage: "rectangle.grid.1x2") }
                NavigationLink { BlockedMembersView(userID: userID) } label: { Label("屏蔽用户", systemImage: "person.slash") }
                Toggle(isOn: $showsBlocked) { Label("显示被屏蔽的内容", systemImage: "eye") }
                NavigationLink { AccountSecurityView(userID: userID) } label: { Label("登录与安全", systemImage: "lock.shield") }
            }
            Section("外观") {
                Picker("显示模式", selection: $appearance) { ForEach(AppAppearance.allCases) { Text($0.title).tag($0) } }
                NavigationLink { WebsitePreferencesView(userID:userID) } label: { Label("官网显示设置",systemImage:"globe") }
            }
            Section {
                Button(account.isSigningOut ? "正在退出" : "退出登录", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmsSignOut = true }
                    .tint(.red).disabled(account.isSigningOut)
            }
        }
        .seekCanvas().listSectionSpacing(20).navigationTitle("账号设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("退出登录？", isPresented: $confirmsSignOut) {
            Button("退出登录", role: .destructive) { Task { await signOut() } }
            Button("取消", role: .cancel) { }
        } message: { Text("草稿会保留。") }
        .alert("未能退出", isPresented: $showsError) { Button("知道了", role: .cancel) { } } message: { Text(error) }
    }
    private func signOut() async {
        do { try await account.signOut() }
        catch { self.error = SiteError.displayMessage(for: error); showsError = true }
    }
}
