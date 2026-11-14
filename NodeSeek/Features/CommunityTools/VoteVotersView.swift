import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct VoteVotersView: View {
    @Environment(AccountSession.self) private var account
    let item: VoteItem
    @State private var voters: [Int] = []
    @State private var page = 0
    @State private var busy = false
    @State private var error: String?
    @State private var reachedEnd = false

    var body: some View {
        List {
            ForEach(voters, id: \.self) { id in
                NavigationLink(value: MemberDestination.profile(id)) { HStack { AvatarView(name: "", url: NodeSeekRoute.origin.appending(path: "avatar/\(id).png")); Text("用户 #\(id)") } }
            }
            if page == 0 || (!reachedEnd && voters.count < (item.count ?? 0)) {
                LoadMoreRow(error: error) { await load() }
                    .id(page)
            }
        }.seekGroupedList().navigationTitle(item.text).navigationBarTitleDisplayMode(.inline)
    }
    private func load() async {
        guard !busy, !reachedEnd else { return }
        busy = true
        defer { busy = false }
        let force = error != nil
        error = nil
        do {
            let result: VotersResponse = try await account.website.load(.voteVoters(itemID: item.id, page: page + 1), force: force)
            try Task.checkCancellation()
            guard result.success else { throw SiteError.invalidResponse }
            var existing = Set(voters)
            let newVoters = result.voters.filter { existing.insert($0).inserted }
            voters.append(contentsOf: newVoters)
            reachedEnd = newVoters.isEmpty
            page += 1
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = SiteError.displayMessage(for: error) } }
    }
}
