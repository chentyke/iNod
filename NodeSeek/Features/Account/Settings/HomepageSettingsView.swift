import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct HomepageSettingsView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var loader = AccountLoader<AccountPage<HomepageCategory>>()
    @State private var categories: [HomepageCategory] = []
    @State private var saved = false
    @State private var initialized = false

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { _ in
            Form {
                Section {
                    ForEach($categories) { $category in Toggle(category.title, isOn: $category.enabled) }
                } header: { Text("在社区首页显示") } footer: { Text("这些选择也会同步到官网。") }
                if saved { Label("已保存", systemImage: "checkmark.circle.fill").foregroundStyle(Color.seekGreen) }
            }.disabled(loader.isUpdating)
        }
        .seekCanvas().listSectionSpacing(20).navigationTitle("首页版块")
        .toolbar { Button(loader.isUpdating ? "保存中" : "保存") { Task { await save() } }.disabled(loader.value == nil || loader.isUpdating || categories == (loader.value?.items ?? [])) }
        .onChange(of: categories) { saved = false }
        .task { await load() }
    }
    private func load(force: Bool = false) async {
        if !initialized, let cached: AccountPage<HomepageCategory> = account.website.cached(key: account.website.key(for: .homepage, viewerID: userID)) {
            categories = cached.items; initialized = true
        }
        await loader.load(account.website, .homepage, userID: userID, force: force)
        if !initialized, let value = loader.value { categories = value.items; initialized = true }
    }
    private func save() async {
        if await loader.action(account.website, .saveHomepage(categories), userID: userID) != nil { saved = true; await account.refresh() }
    }
}
