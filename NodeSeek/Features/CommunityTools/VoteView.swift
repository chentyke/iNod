import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct VoteView: View {
    let voteID: Int
    @Environment(AccountSession.self) private var account
    @State private var vote: ForumVote?
    @State private var selected: Set<Int> = []
    @State private var error: String?
    @State private var busy = false
    @State private var confirmsVote = false
    @State private var confirmsLock = false
    @State private var votersItem: VoteItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(vote?.title ?? "投票", image: .inkPoll).font(.headline)
            if let vote {
                Text("\(vote.multiple ? "多选" : "单选") · \(vote.isPublic ? "公开投票" : "匿名投票")\(vote.locked ? " · 已结束" : "")").font(.caption).foregroundStyle(.secondary)
                ForEach(vote.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            if !vote.multiple { selected = [item.id] }
                            else if !selected.insert(item.id).inserted { selected.remove(item.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(selected.contains(item.id) || item.voted == true ? .inkVoted : .inkVoteOption).foregroundStyle(Color.seekButtonIcon)
                                Text(item.text).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                Spacer()
                                if vote.hasVoted || vote.locked { Text(item.count.map { $0.formatted() } ?? "—").foregroundStyle(.secondary).monospacedDigit() }
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).disabled(vote.hasVoted || vote.locked || busy)
                        if vote.hasVoted || vote.locked {
                            if let count = item.count,let total = vote.total { ProgressView(value: Double(count), total: Double(max(1,total))).tint(.seekGreen) }
                            if vote.isPublic && (item.count ?? 0) > 0 { Button("查看投票用户") { votersItem = item }.font(.caption).frame(minHeight: 44) }
                        }
                    }
                }
                if !vote.hasVoted && !vote.locked {
                    Button(account.signInStatus == .signedOut ? "登录后投票" : "提交投票") { confirmsVote = true }
                        .buttonStyle(.seekPill)
                        .disabled(selected.isEmpty || busy || account.signInStatus != .signedIn)
                } else { Text(vote.total.map { "\(vote.hasVoted ? "已投票 · " : "")共 \($0) 票" } ?? "暂无可显示的统计").font(.caption).foregroundStyle(.secondary) }
                if vote.uid == account.user?.id && !vote.locked { Button("结束投票", role: .destructive) { confirmsLock = true }.disabled(busy) }
            } else if error == nil { ProgressView("正在读取投票") }
            if let error { Text(error).font(.subheadline).foregroundStyle(.secondary); Button("重试") { Task { await load(force: true) } } }
        }.padding(16).background(Color.seekTray.opacity(0.6), in: .rect(cornerRadius: 16))
        .task(id: "\(voteID)|\(account.revision)") { await load() }
        .confirmationDialog("确认提交投票？", isPresented: $confirmsVote, titleVisibility: .visible) {
            Button("提交投票") { Task { await submit(lock: false) } }; Button("取消", role: .cancel) { }
        } message: { Text("提交后不能更改。公开投票会显示参与者。") }
        .confirmationDialog("结束这次投票？", isPresented: $confirmsLock, titleVisibility: .visible) {
            Button("结束投票", role: .destructive) { Task { await submit(lock: true) } }; Button("取消", role: .cancel) { }
        } message: { Text("结束后普通用户不能重新开启。") }
        .sheet(item: $votersItem) { item in ForumNavigationStack { VoteVotersView(item: item) } }
    }
    private func load(force: Bool = false) async {
        error = nil
        do {
            let result: VoteResponse = try await account.website.load(.vote(voteID), force: force)
            try Task.checkCancellation(); vote = result.vote
            if result.vote.hasVoted || result.vote.locked {
                selected = Set(result.vote.items.filter { $0.voted == true }.map(\.id))
            } else {
                selected.formIntersection(result.vote.items.map(\.id))
            }
        } catch { if !Task.isCancelled { self.error = SiteError.displayMessage(for: error) } }
    }
    private func submit(lock: Bool) async {
        guard !busy, account.signInStatus == .signedIn, let userID = account.user?.id else { return }
        busy = true
        defer { busy = false }
        do {
            let _: ReactionResponse = try await account.website.perform(lock ? .lockVote(id: voteID) : .vote(items: selected.sorted()), userID: userID)
            await load(force: true)
        } catch { self.error = SiteError.displayMessage(for: error) }
    }
}
