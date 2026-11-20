import NodeSeekClient
import NodeSeekCore
import SwiftUI

struct MemberMentionView: View {
    let name: String
    @Environment(AccountSession.self) private var account
    @State private var loader = ResourceLoader<MemberSearchResponse>()

    var body: some View {
        ResourceContent(loader: loader, retry: { await load(force: true) }) { result in
            if let member = result.memberList.first(where: { $0.member_name.caseInsensitiveCompare(name) == .orderedSame }) {
                ProfileView(userID: member.id)
            } else {
                ContentUnavailableView("没有找到 @\(name)", image: .inkMissingMember)
            }
        }
        .task(id: account.revision) { await load() }
    }

    private func load(force: Bool = false) async {
        await loader.load(account.website, .memberSearch(name), force: force)
    }
}
