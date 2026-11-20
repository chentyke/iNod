import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct HomepageSettingsView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var loader = ResourceLoader<AccountPage<HomepageCategory>>()
    @State private var categories: [HomepageCategory] = []
    @State private var baselineCategories: [HomepageCategory] = []
    @State private var saved = false
    @State private var initialized = false

    private var enabledCount: Int {
        categories.filter(\.enabled).count
    }

    private var hasChanges: Bool {
        initialized && categories != baselineCategories
    }

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { _ in
            List {
                if saved && !hasChanges {
                    Section {
                        SettingsFeedbackRow(message: "首页版块设置已同步到 NodeSeek。", isSuccess: true)
                            .listRowBackground(Color.seekCard)
                    }
                }

                Section {
                    if categories.isEmpty {
                        Text("暂无可自定义的版块")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                            .listRowBackground(Color.seekCard)
                    }

                    ForEach($categories) { $category in
                        Toggle(isOn: $category.enabled) {
                            HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                                SeekIconTile(
                                    symbol: category.inkIcon,
                                    tint: category.enabled ? .categoryTint(category.id) : .seekInk
                                )
                                Text(category.title)
                                    .foregroundStyle(Color.seekInk)
                            }
                            .frame(minHeight: 44)
                        }
                        .tint(Color.seekGreen)
                        .accessibilityIdentifier("homepage-category-\(category.id)")
                        .settingsRowStyle()
                    }
                } header: {
                    SeekSectionTitle(
                        title: "首页显示版块",
                        detail: categories.isEmpty ? nil : "已开启 \(enabledCount) / \(categories.count)"
                    )
                } footer: {
                    Text("关闭后，对应版块的主题将不在首页综合流中显示，仍可单独进入版块浏览。选择会同步到 NodeSeek 官网。")
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
            .disabled(loader.updating)
        }
        .navigationTitle("首页版块")
        .interactiveDismissDisabled(loader.updating)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(loader.updating ? "保存中…" : "保存") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(loader.value == nil || loader.updating || !hasChanges)
                .accessibilityIdentifier("homepage-save-button")
            }
        }
        .onChange(of: categories) {
            if hasChanges { saved = false }
        }
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        if !initialized,
           let cached: AccountPage<HomepageCategory> = account.website.cached(
               key: account.website.key(for: .homepage, viewerID: userID)
           ) {
            apply(cached.items)
        }
        let hadEditsBeforeLoad = hasChanges
        await loader.load(account.website, .homepage, userID: userID, force: force)
        if let value = loader.value, (!initialized || !hadEditsBeforeLoad || force) {
            apply(value.items)
        }
    }

    private func apply(_ items: [HomepageCategory]) {
        categories = items
        baselineCategories = items
        initialized = true
    }

    private func save() async {
        guard hasChanges else { return }
        if await loader.action(account.website, .saveHomepage(categories), userID: userID) != nil {
            baselineCategories = categories
            loader.value = AccountPage(items: categories, hasNext: false)
            saved = true
            await account.refresh()
        }
    }
}
