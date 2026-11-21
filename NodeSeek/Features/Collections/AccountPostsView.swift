import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct AccountPostsView: View {
    let kind: AccountContentKind
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var loader = ResourceLoader<AccountPage<AccountPost>>()
    @State private var page = 1
    @State private var loadedRevision: String?
    @State private var removing: AccountPost?
    @State private var confirmsRemoval = false
    @State private var removalError: String?
    @State private var showsRemovalError = false

    private var revision: String { "\(account.revision)|\(kind == .collections ? account.collections.revision : 0)" }

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { data in
            let items = kind == .collections ? data.items.filter { account.collections.status($0.postID) != false } : data.items
            List {
                if items.isEmpty {
                    ContentUnavailableView("暂无\(kind == .collections ? "收藏" : kind == .replies ? "回复" : "主题")", image: kind.symbol)
                        .listRowSeparator(.hidden)
                }
                ForEach(items) { item in
                    NavigationLink(value:item) { AccountPostRow(item: item) }
                        .listRowSeparator(.visible, edges: .bottom)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if kind == .collections {
                                Button("取消收藏", image: .inkUnsavePost, role: .destructive) { removing = item; confirmsRemoval = true }
                                    .disabled(account.collections.updating.contains(item.postID))
                            }
                        }
                }
                if data.hasNext && loader.error == nil && !loader.isLoadingFirstPage && loadedRevision == revision {
                    LoadMoreRow(error: loader.nextPageError) { await load(nextPage: true) }
                        .id(page)
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
        }
        .navigationTitle(account.user?.id == userID ? kind.title : (kind == .replies ? "回复" : "主题"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: revision) {
            if loadedRevision != revision { await load() }
        }
        .refreshable { await load(force: true) }
        .confirmationDialog("取消这篇帖子的收藏？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("取消收藏", role: .destructive) { Task { await remove() } }
            Button("保留", role: .cancel) { removing = nil }
        }
        .alert("未能取消收藏", isPresented: $showsRemovalError) {
            Button("重试") { Task { await remove() } }
            Button("取消", role: .cancel) { removing = nil }
        } message: { Text(removalError ?? "") }
    }

    private func load(force: Bool = false, nextPage: Bool = false) async {
        let revision = revision
        guard !nextPage || (loadedRevision == revision && loader.value?.hasNext == true) else { return }
        let requestedPage = nextPage ? page + 1 : 1
        let resource = AccountResource.content(kind, userID: userID, page: requestedPage)
        let force = force || (nextPage && loader.nextPageError != nil)
        let merge = nextPage ? appendPage(\AccountPage<AccountPost>.items) : nil
        let data: AccountPage<AccountPost>?
        if resource.isPublic {
            data = await loader.loadPublic(account.website, resource, viewerID: account.user?.id, force: force, appending: merge)
        } else {
            let sessionRevision = account.revision
            let collectionRevision = account.collections.revision
            data = await loader.load(account.website, resource, userID: userID, force: force, appending: merge)
            if let data, account.revision == sessionRevision {
                account.collections.observe(data.items.map(\.postID), collected: true, expectedRevision: collectionRevision)
            }
        }
        if data != nil, self.revision == revision {
            page = requestedPage
            loadedRevision = revision
        }
    }
    private func remove() async {
        guard let removing, account.user?.id == userID else { return }
        do {
            try await account.collections.setCollected(false, postID: removing.postID)
            self.removing = nil
        } catch is CancellationError {
            self.removing = nil
        } catch {
            removalError = SiteError.displayMessage(for: error)
            showsRemovalError = true
        }
    }
}
