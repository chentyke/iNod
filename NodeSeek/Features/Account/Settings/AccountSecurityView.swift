import NodeSeekCore
import NodeSeekClient
import SwiftUI
import UIKit

struct AccountSecurityView: View {
    @Environment(AccountSession.self) private var account
    let userID: Int
    @State private var loader = ResourceLoader<AccountSecurity>()

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { data in
            List {
                Section {
                    NavigationLink {
                        PasswordView(userID: userID)
                    } label: {
                        SettingsRowContent(
                            title: "修改密码",
                            subtitle: "更换当前账号的登录密码",
                            symbol: .inkPassword
                        )
                    }
                    .accessibilityIdentifier("security-row-password")
                    .settingsRowStyle()

                    NavigationLink {
                        TwoFactorView(userID: userID)
                    } label: {
                        SettingsRowContent(
                            title: "双因素验证",
                            subtitle: "登录时校验动态验证码",
                            symbol: data.twoFactorEnabled ? .inkTwoFactorOn : .inkTwoFactor,
                            tint: data.twoFactorEnabled ? .seekGreen : .seekInk,
                            badge: (data.twoFactorEnabled ? "已开启" : "未开启", data.twoFactorEnabled)
                        )
                    }
                    .accessibilityIdentifier("security-row-2fa")
                    .settingsRowStyle()

                    NavigationLink {
                        TelegramSettingsView(userID: userID)
                    } label: {
                        SettingsRowContent(
                            title: "Telegram 提醒",
                            subtitle: "接收私信、回复与 @提及 通知",
                            symbol: .inkTelegramAlerts
                        )
                    }
                    .accessibilityIdentifier("security-row-telegram")
                    .settingsRowStyle()

                    OfficialSettingsLink(
                        title: "邮箱与手机号",
                        symbol: .inkRecoveryContacts,
                        anchor: "contact",
                        description: "更换绑定需在官网完成验证码"
                    )
                    .accessibilityIdentifier("security-row-contact")
                    .settingsRowStyle(alignSeparator: false)
                } header: {
                    SeekSectionTitle(title: "验证与绑定")
                }

                Section {
                    if data.history.isEmpty {
                        Text("暂无最近登录记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.seekCard)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(Array(data.history.enumerated()), id: \.element.id) { index, record in
                        LoginRecordRow(record: record, isLatest: index == 0)
                            .settingsRowStyle()
                    }
                } header: {
                    SeekSectionTitle(
                        title: "最近登录",
                        detail: data.history.isEmpty ? nil : "\(data.history.count) 条"
                    )
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
        }
        .navigationTitle("登录与安全")
        .task { await load() }
        .onAppear {
            guard loader.value != nil, !loader.loading else { return }
            let key = account.website.key(for: .security, viewerID: userID)
            let cached: AccountSecurity? = account.website.cached(key: key, allowingStale: false)
            if cached == nil {
                Task { await load(force: true) }
            }
        }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        await loader.load(account.website, .security, userID: userID, force: force)
    }
}

private struct LoginRecordRow: View {
    let record: LoginRecord
    let isLatest: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: AccountSettingsMetrics.rowSpacing) {
            SeekIconTile(
                symbol: isLatest ? .inkLatestLogin : .inkLoginAddress,
                tint: isLatest ? .seekGreen : .seekInk
            )

            VStack(alignment: .leading, spacing: 4) {
                let headerLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                headerLayout {
                    Text(record.ip)
                        .font(.body.monospaced().weight(.medium))
                        .foregroundStyle(Color.seekInk)
                        .textSelection(.enabled)
                    if isLatest {
                        SettingsStatusPill(text: "最近一次", active: true)
                    }
                }

                ForumDateText(value: record.createdAt)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: AccountSettingsMetrics.iconSize)
        .contentShape(.rect)
        .contextMenu {
            Button("复制 IP 地址", image: .inkCopyAddress) {
                UIPasteboard.general.string = record.ip
            }
        }
        .accessibilityIdentifier("login-record-\(record.id)")
    }
}
