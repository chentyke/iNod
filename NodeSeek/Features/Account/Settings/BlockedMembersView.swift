import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct BlockedMembersView: View {
    @Environment(AccountSession.self) private var account
    let userID: Int
    @State private var loader = AccountLoader<AccountPage<BlockedMember>>()
    @State private var name = ""
    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { data in
            List {
                Section {
                    TextField("要屏蔽的用户名", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(loader.isUpdating)
                    Button("添加屏蔽", systemImage: "person.badge.minus") { Task { await add() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loader.isUpdating)
                }
                Section("已屏蔽") {
                    if data.items.isEmpty { ContentUnavailableView("没有屏蔽的用户", systemImage: "person.slash") }
                    ForEach(data.items) { member in
                        HStack(spacing: 12) {
                            AvatarView(name: member.name, url: NodeSeekRoute.origin.appending(path: "avatar/\(member.id).png"))
                            Text(member.name)
                            Spacer()
                            Button("解除") { Task { await remove(member.id) } }.buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44).disabled(loader.isUpdating)
                        }.padding(.vertical, 5)
                    }
                }
            }
        }
        .seekGroupedList().navigationTitle("屏蔽用户")
        .task { await load() }
        .refreshable { await load(force: true) }
    }
    private func load(force: Bool = false) async { await loader.load(account.website, .blocks, userID: userID, force: force) }
    private func add() async {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if await loader.action(account.website, .block(name: value), userID: userID) != nil { name = ""; await load() }
    }
    private func remove(_ id: Int) async {
        if await loader.action(account.website, .unblock(memberID: id), userID: userID) != nil { await load() }
    }
}
