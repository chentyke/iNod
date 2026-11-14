import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct LuckyView: View {
    @Environment(AccountSession.self) private var account
    var initial: LuckyDraw?
    @State private var post = ""
    @State private var revealTime = Date.now.addingTimeInterval(3600)
    @State private var count = "1"
    @State private var floor = "1"
    @State private var removeDuplicates = true
    @State private var winners: [LuckyFloor]?
    @State private var error: String?
    @State private var busy = false
    @State private var pastedLink = ""
    private var draw: LuckyDraw? {
        guard let address = PostAddress(post),let count = Int(count),let first = Int(floor) else { return nil }
        let draw = LuckyDraw(postID:address.id,revealTime:revealTime,count:count,firstFloor:first,removeDuplicates:removeDuplicates)
        return draw.valid ? draw : nil
    }
    var body: some View {
        Form {
            Section("抽奖设置") {
                TextField("帖子链接或编号", text:$post).textInputAutocapitalization(.never).autocorrectionDisabled()
                DatePicker("开奖时间",selection:$revealTime)
                TextField("中奖人数",text:$count).keyboardType(.numberPad)
                TextField("起始楼层",text:$floor).keyboardType(.numberPad)
                Toggle("每位用户只参与一次",isOn:$removeDuplicates)
            }
            if let draw {
                Section {
                    ShareLink("分享开奖链接",item:draw.url)
                    ShareLink("分享 Markdown 链接",item:"[开奖链接](\(draw.url.absoluteString))")
                    Button(busy ? "正在开奖…" : "查看开奖结果",systemImage:"gift") { Task { await load(draw) } }.disabled(busy)
                } footer: { Text("参与者来自指定帖子，结果使用与官网相同的公开随机数和算法。开奖前可以先分享链接。") }
            }
            Section("打开已有抽奖") {
                TextField("粘贴 NodeSeek 开奖链接",text:$pastedLink).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("读取设置") {
                    if let url = URL(string:pastedLink),let parsed = LuckyDraw(url:url) { apply(parsed) }
                    else { error = "请输入完整的 NodeSeek 开奖链接。" }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.secondary) } }
            if let winners {
                Section("开奖结果") {
                    if winners.isEmpty { Text("没有符合条件的参与者。") }
                    ForEach(winners) { winner in
                        NavigationLink(value:MemberDestination.profile(winner.member_id)) { LabeledContent(winner.member_name,value:"#\(winner.floor_id)") }
                    }
                    if let draw, !winners.isEmpty {
                        ShareLink("分享中奖名单",item:winners.map { EditorDraft.replyReference(postID:draw.postID,floor:$0.floor_id,name:$0.member_name) }.joined(separator:" ") + "恭喜中奖🎁")
                    }
                }
            }
        }.seekCanvas().listSectionSpacing(20).navigationTitle("抽奖工具").navigationBarTitleDisplayMode(.inline).toolbar(.hidden,for:.tabBar)
        .task { if let initial { apply(initial); await load(initial) } }
    }
    private func apply(_ draw: LuckyDraw) { post = String(draw.postID); revealTime = draw.revealTime; count = String(draw.count); floor = String(draw.firstFloor); removeDuplicates = draw.removeDuplicates; winners = nil; error = nil }
    private func load(_ draw: LuckyDraw) async {
        guard !busy else { return }
        guard draw.revealTime < .now else { error = "还没到开奖时间：\(draw.revealTime.formatted())"; return }
        busy = true; error = nil; winners = nil; defer { busy = false }
        do {
            let result = try await account.website.drawWinners(draw)
            try Task.checkCancellation()
            winners = result
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
