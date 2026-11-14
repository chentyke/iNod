import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct RulingsView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.openMemberDestination) private var openMember
    let recordID: Int?
    let openDestination: (AppDestination) -> Void
    @State private var loader = ResourceLoader<RulingPage>()
    @State private var query = ""
    @State private var submitted = ""
    @State private var page = 1
    @State private var loadedSearch: String?
    var body: some View {
        ResourceContent(loader:loader,websiteURL:NodeSeekRoute.origin.appending(path:"ruling"),retry:{ await load(force:true) }) { data in
            List {
                ForEach(data.data) { record in
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            Button(record.target_member_name) { openMember(.profile(record.target_member_id)) }
                            Spacer()
                            Button("#\(record.id)") { openDestination(.rulings(recordID: record.id)) }
                                .font(.caption.monospaced())
                        }
                        Text(record.description).font(.subheadline).textSelection(.enabled)
                        if let post = PostAddress(String(record.post_id)) {
                            Button("查看关联\(record.floor_index == 0 ? "帖子" : "回复")") {
                                let page = record.floor_index <= 10 ? 1 : (record.floor_index - 1) / 10 + 1
                                openDestination(.post(post.summary, page: page, floor: nil))
                            }
                            .font(.subheadline)
                        }
                        HStack { Text("处理人：\(record.admin_member_name)"); Spacer(); ForumDateText(value:record.created_at) }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,10).contextMenu { ShareLink(item:URL(string:"https://www.nodeseek.com/ruling#/id-\(record.id)")!) }
                }
                if data.data.isEmpty { ContentUnavailableView("暂无记录",systemImage:"list.bullet.rectangle") }
                if hasNextPage(data) && loader.error == nil && !loader.isLoadingFirstPage && loadedSearch == submitted {
                    LoadMoreRow(error: loader.nextPageError) { await load(nextPage: true) }
                        .id(page)
                }
            }
        }.buttonStyle(.borderless).seekGroupedList().navigationTitle(recordID == nil ? "管理记录" : "记录详情").searchable(text:$query,prompt:"搜索用户名")
        .onSubmit(of:.search) { submitted = query.trimmingCharacters(in:.whitespacesAndNewlines) }
        .onChange(of:query) { if query.isEmpty { submitted = "" } }
        .task(id: submitted) { if loadedSearch != submitted { await load() } }
        .refreshable { await load(force:true) }
    }

    private func hasNextPage(_ data: RulingPage) -> Bool {
        recordID == nil && page < 100 && page * 20 < data.total
    }


    private func load(force: Bool = false, nextPage: Bool = false) async {
        let search = submitted
        if nextPage {
            guard loadedSearch == search, let data = loader.value, hasNextPage(data) else { return }
        }
        let requestedPage = nextPage ? page + 1 : 1
        let force = force || (nextPage && loader.nextPageError != nil)
        let merge = nextPage ? appendPage(\RulingPage.data) : nil
        if await loader.load(account.website, .rulings(recordID: recordID, page: requestedPage, search: submitted), force: force, appending: merge) != nil,
           search == submitted {
            page = requestedPage
            loadedSearch = search
        }
    }
}
