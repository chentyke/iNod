import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct MemberSearchView: View {
    @Environment(AccountSession.self) private var account
    @State private var query = ""
    @State private var submitted = ""
    @State private var loader = ResourceLoader<MemberSearchResponse>()
    var body: some View {
        Group {
            if submitted.isEmpty { ContentUnavailableView("搜索社区用户",systemImage:"person.crop.circle.badge.magnifyingglass",description:Text("输入用户名，打开主页或发起私聊。")) }
            else {
                ResourceContent(loader:loader,retry:{ await search(force:true) }) { result in
                    List {
                        if result.memberList.isEmpty { ContentUnavailableView("没有找到用户",systemImage:"person.crop.circle.badge.questionmark") }
                        ForEach(result.memberList) { member in
                            NavigationLink(value:MemberDestination.profile(member.id)) {
                                HStack(spacing:12) {
                                    AvatarView(name:member.member_name,url:NodeSeekRoute.origin.appending(path:"avatar/\(member.id).png"),size:44)
                                    VStack(alignment:.leading,spacing:5) { Text(member.member_name).font(.headline); if let bio = member.bio,!bio.isEmpty { Text(bio).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) } }
                                }.padding(.vertical,6)
                            }
                        }
                    }.seekGroupedList()
                }
            }
        }.searchable(text:$query,prompt:"搜索用户").navigationTitle("用户搜索").navigationBarTitleDisplayMode(.inline)
        .onSubmit(of:.search) { submitted = query.trimmingCharacters(in:.whitespacesAndNewlines) }
        .onChange(of:query) { if query.isEmpty { submitted = "" } }
        .task(id:submitted) { if !submitted.isEmpty { await search() } }
    }
    private func search(force: Bool = false) async {
        await loader.load(account.website, .memberSearch(submitted),force:force)
    }
}
