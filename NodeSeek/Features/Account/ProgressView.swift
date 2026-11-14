import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct AccountProgressView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var loader = ResourceLoader<DailyProgress>()
    var body: some View {
        ResourceContent(loader:loader,retry:{ await load(force:true) }) { data in
            List {
                Section("社区等级") {
                    let level = account.user?.level ?? 0
                    VStack(alignment:.leading,spacing:12) {
                        HStack { Text("Lv \(level)").font(.largeTitle.bold()); Spacer(); Label("\(account.user?.coins ?? 0) 鸡腿",systemImage:"fork.knife").font(.subheadline).foregroundStyle(.secondary) }
                        if level < 6 {
                            let minimum = 100 * level * level, maximum = 100 * (level + 1) * (level + 1)
                            SwiftUI.ProgressView(value:Double(max(0,(account.user?.coins ?? 0)-minimum)),total:Double(maximum-minimum)).tint(.seekGreen)
                            Text("距离 Lv \(level + 1) 还需 \(max(0,maximum-(account.user?.coins ?? 0))) 个鸡腿").font(.caption).foregroundStyle(.secondary)
                        } else { Text("已达到最高等级").font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.vertical,12)
                }
                Section("今日进度") {
                    row("发帖奖励次数",current:data.postBonusCount,total:data.maxPostBonusCount)
                    row("回复奖励次数",current:data.commentBonusCount,total:data.maxCommentBonusCount)
                    row("免费鸡腿",current:data.freeLikeUsed,total:data.maxFreeLike)
                    NavigationLink { AttendanceView(userID:userID) } label: { Label("签到与排行榜",systemImage:"calendar.badge.checkmark") }
                }
            }
        }.seekGroupedList().navigationTitle("等级与进度").task { await load() }.refreshable { await load(force:true); await account.refresh(force:true) }
    }
    private func row(_ title: String,current: Int,total: Int) -> some View {
        VStack(alignment:.leading,spacing:10) { LabeledContent(title,value:"\(current) / \(total)"); SwiftUI.ProgressView(value:Double(min(current,total)),total:Double(max(1,total))).tint(.seekGreen) }.padding(.vertical,8)
    }
    private func load(force: Bool = false) async { await loader.load(account.website, .dailyProgress,force:force) }
}
