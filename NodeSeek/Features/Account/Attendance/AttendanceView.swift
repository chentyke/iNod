import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct AttendanceView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var loader = AccountLoader<AttendanceBoard>()
    @State private var page = 1

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { data in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(data.gain == nil ? "今天还未签到" : "今天已签到", systemImage: data.gain == nil ? "calendar" : "checkmark.circle.fill")
                            .font(.title3.bold()).foregroundStyle(Color.seekGreen)
                        if let gain = data.gain {
                            Text("获得 \(gain) 个鸡腿").font(.headline)
                            if let order = data.order { Text("今日第 \(order) 位签到").font(.subheadline).foregroundStyle(.secondary) }
                        } else {
                            Button("签到，领取 5 个鸡腿", systemImage: "checkmark") { Task { await signIn(random: false) } }
                                .buttonStyle(.seekPill)
                            Button("试试手气，领取随机奖励", systemImage: "dice") { Task { await signIn(random: true) } }
                                .buttonStyle(.borderless).frame(minHeight: 44)
                        }
                        if loader.isUpdating { ProgressView("正在签到") }
                    }.padding(.vertical, 12).disabled(loader.isUpdating)
                }
                Section("今日签到榜（\(data.total) 人）") {
                    ForEach(data.items) { member in
                        HStack(spacing: 12) {
                            Text(member.rank.formatted()).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 28)
                            AvatarView(name: member.name, url: NodeSeekRoute.origin.appending(path: "avatar/\(member.id).png"))
                            Text(member.name).lineLimit(1)
                            Spacer()
                            Text("+\(member.gain)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Color.seekGreen)
                        }.padding(.vertical, 5).accessibilityElement(children: .combine)
                    }
                    if data.hasNext && loader.error == nil && !loader.isLoadingFirstPage {
                        LoadMoreRow(error: loader.nextPageError, isEnabled: !loader.isUpdating) {
                            await load(nextPage: true)
                        }
                        .id(page)
                    }
                }
            }
        }
        .seekGroupedList().navigationTitle("每日签到")
        .task { if loader.value == nil { await load() } }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false, nextPage: Bool = false) async {
        guard !nextPage || loader.value?.hasNext == true else { return }
        let requestedPage = nextPage ? page + 1 : 1
        let force = force || (nextPage && loader.nextPageError != nil)
        let merge = nextPage ? appendPage(\AttendanceBoard.items) : nil
        if await loader.load(account.website, .attendance(requestedPage), userID: userID, force: force, appending: merge) != nil {
            page = requestedPage
        }
    }
    private func signIn(random: Bool) async {
        guard loader.value?.gain == nil, !loader.isUpdating else { return }
        if let response = await loader.action(account.website, .attend(random: random), userID: userID) {
            account.updateCoins(response.current)
            await load()
            await account.refresh()
        }
    }
}
