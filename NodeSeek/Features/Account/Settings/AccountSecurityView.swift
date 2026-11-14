import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct AccountSecurityView: View {
    @Environment(AccountSession.self) private var account
    let userID: Int
    @State private var loader = AccountLoader<AccountSecurity>()
    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { data in
            List {
                Section("账号安全") {
                    NavigationLink { PasswordView(userID:userID) } label: { Label("修改密码",systemImage:"key") }
                    NavigationLink { TwoFactorView(userID:userID) } label: { LabeledContent("双因素验证", value: data.twoFactorEnabled ? "已开启" : "未开启") }
                    NavigationLink { TelegramSettingsView(userID: userID) } label: { Label("Telegram 提醒", systemImage: "paperplane") }
                    OfficialSettingsLink(title:"邮箱与手机号",anchor:"contact",description:"更换绑定需要官网完成验证码。")
                }
                Section("最近登录") {
                    if data.history.isEmpty { ContentUnavailableView("暂无登录记录", systemImage: "clock") }
                    ForEach(data.history) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(record.ip).font(.body.monospaced()).textSelection(.enabled)
                            ForumDateText(value: record.createdAt).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
            }
        }
        .seekGroupedList().navigationTitle("登录与安全")
        .task { await load() }
        .refreshable { await load(force: true) }
    }
    private func load(force: Bool = false) async { await loader.load(account.website, .security, userID: userID, force: force) }
}
