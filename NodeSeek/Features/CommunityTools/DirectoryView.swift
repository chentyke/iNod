import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct DirectoryView: View {
    @Environment(AccountSession.self) private var account
    let providers: Bool
    @State private var loader = ResourceLoader<[DirectoryEntry]>()
    @State private var query = ""
    private var url: URL { NodeSeekRoute.origin.appending(path:providers ? "providers" : "friends") }
    var body: some View {
        ResourceContent(loader:loader,websiteURL:url,retry:{ await load(force:true) }) { entries in
            List(entries.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { entry in
                if let id = MemberAddress.parse(entry.url.absoluteString) {
                    NavigationLink(value:MemberDestination.profile(id)) { row(entry) }
                } else { Link(destination:entry.url) { row(entry) } }
            }.seekGroupedList()
        }.navigationTitle(providers ? "合作商家" : "友情链接").searchable(text:$query,prompt:"搜索名称")
        .task { await load() }.refreshable { await load(force:true) }
    }
    private func row(_ entry: DirectoryEntry) -> some View {
        HStack(spacing:14) {
            AsyncImage(url:entry.image) { image in image.resizable().scaledToFit() } placeholder: { Image(providers ? .inkMerchant : .inkFriendLink).foregroundStyle(Color.seekGreen) }
                .frame(width:48,height:48).padding(4).background(.white,in:.rect(cornerRadius:10))
            VStack(alignment:.leading,spacing:5) { Text(entry.title).font(.headline).foregroundStyle(.primary); if !providers { Text(entry.url.host() ?? "").font(.caption).foregroundStyle(.secondary) } }
            Spacer()
        }.padding(.vertical,6)
    }
    private func load(force: Bool = false) async { await loader.load(account.website, .directory(providers: providers), force:force) }
}
