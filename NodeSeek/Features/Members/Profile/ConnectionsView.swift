import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct ConnectionsView: View {
    @Environment(AccountSession.self) private var account
    let follows: Bool
    let userID: Int
    @State private var loader = ResourceLoader<MemberSearchResponse>()
    var body: some View {
        ResourceContent(loader:loader,retry:{ await load(force:true) }) { result in
            List {
                if result.memberList.isEmpty { ContentUnavailableView(follows ? "还没有关注用户" : "还没有粉丝",systemImage:"person.2") }
                ForEach(result.memberList) { member in
                    NavigationLink(value:MemberDestination.profile(member.id)) {
                        HStack(spacing:12) {
                            AvatarView(name:member.member_name,url:NodeSeekRoute.origin.appending(path:"avatar/\(member.id).png"),size:44)
                            VStack(alignment:.leading,spacing:5) { Text(member.member_name).font(.headline); if let bio = member.bio,!bio.isEmpty { Text(bio).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) } }
                        }.padding(.vertical,6)
                    }
                }
            }.seekGroupedList()
        }.navigationTitle(follows ? "我的关注" : "我的粉丝").task { await load() }.refreshable { await load(force:true) }
    }
    private func load(force: Bool = false) async { await loader.load(account.website, .connections(follows: follows),force:force) }
}
