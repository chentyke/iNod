import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct LedgerView: View {
    let kind: LedgerKind
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var loader = AccountLoader<AccountPage<LedgerEntry>>()
    @State private var page = 1
    @State private var lastCursor: Int?

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { data in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(kind == .chicken ? "当前鸡腿" : "当前星尘", systemImage: kind.symbol).foregroundStyle(.secondary)
                        Text((kind == .chicken ? account.user?.coins : account.user?.stardust).map { $0.formatted() } ?? "—")
                            .font(.largeTitle.bold().monospacedDigit())
                    }.padding(.vertical, 12)
                }
                Section("收支记录") {
                    if data.items.isEmpty { ContentUnavailableView("暂无记录", systemImage: "list.bullet.rectangle") }
                    ForEach(data.items) { LedgerRow(entry: $0) }
                    if hasNextPage(data) && loader.error == nil && !loader.isLoadingFirstPage {
                        LoadMoreRow(error: loader.nextPageError) { await load(nextPage: true) }
                            .id(page)
                    }
                }
            }
        }
        .seekGroupedList().navigationTitle(kind.title)
        .toolbar { if kind == .stardust { NavigationLink { StardustTransferView(userID:userID) } label: { Label("转账",systemImage:"paperplane") } } }
        .task { if loader.value == nil { await load() } }
        .refreshable { await load(force: true); await account.refresh() }
    }

    private func hasNextPage(_ data: AccountPage<LedgerEntry>) -> Bool {
        data.hasNext && (kind == .chicken || (data.cursor != nil && data.cursor != lastCursor))
    }

    private func load(force: Bool = false, nextPage: Bool = false) async {
        if nextPage {
            guard let data = loader.value, hasNextPage(data) else { return }
        }
        let requestedPage = nextPage ? page + 1 : 1
        let cursor = nextPage && kind == .stardust ? loader.value?.cursor : nil
        let resource: AccountResource = kind == .chicken ? .credit(requestedPage) : .stardust(userID: userID, cursor: cursor)
        let force = force || (nextPage && loader.nextPageError != nil)
        let merge = nextPage ? appendPage(\AccountPage<LedgerEntry>.items) : nil
        if await loader.load(account.website, resource, userID: userID, force: force, appending: merge) != nil {
            page = requestedPage
            lastCursor = cursor
        }
    }
}
