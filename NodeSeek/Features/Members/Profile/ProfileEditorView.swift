import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct ProfileEditorView: View {
    let userID: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSession.self) private var account
    @State private var loader = AccountLoader<AccountProfile>()
    @State private var bio = ""
    @State private var signature = ""
    @State private var readme = ""
    @State private var initialized = false

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { _ in
            Form {
                Section("一句话介绍") { TextField("介绍一下自己", text: $bio, axis: .vertical).lineLimit(2...4) }
                Section { TextField("在回复下方显示的签名", text: $signature, axis: .vertical).lineLimit(3...6) } header: { Text("签名") } footer: { Text("支持 Markdown，不支持图片和引用。") }
                Section("个人介绍 · Markdown") { TextField("写在个人主页上的介绍", text: $readme, axis: .vertical).lineLimit(8...20) }
            }.disabled(loader.isUpdating)
        }
        .seekCanvas().listSectionSpacing(20).navigationTitle("编辑资料")
        .toolbar {
            Button(loader.isUpdating ? "保存中" : "保存") { Task { await save() } }
                .disabled(loader.value == nil || loader.isUpdating || !changed)
        }
        .task { await load() }
    }
    private var changed: Bool { bio != (loader.value?.bio ?? "") || signature != (loader.value?.signature ?? "") || readme != (loader.value?.readme ?? "") }
    private func load(force: Bool = false) async {
        if !initialized, let cached: AccountProfile = account.website.cached(key: account.website.key(for: .editableProfile(userID), viewerID: userID)) {
            apply(cached)
        }
        await loader.load(account.website, .editableProfile(userID), userID: userID, force: force)
        if !initialized, let profile = loader.value { apply(profile) }
    }
    private func apply(_ profile: AccountProfile) {
        bio = profile.bio ?? ""; signature = profile.signature ?? ""; readme = profile.readme ?? ""
        initialized = true
    }
    private func save() async {
        guard changed else { return }
        if await loader.action(account.website, .updateProfile(bio: bio, signature: signature, readme: readme), userID: userID) != nil {
            await account.refresh(); dismiss()
        }
    }
}
