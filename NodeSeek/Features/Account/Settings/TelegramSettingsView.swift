import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct TelegramSettingsView: View {
    @Environment(AccountSession.self) private var account
    let userID: Int
    @State private var detail: TelegramAccount?
    @State private var bound: Bool?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmsUnbind = false
    @State private var showsWebsite = false

    var body: some View {
        Form {
            if let bound {
                Section("当前绑定") {
                    Label(bound ? "已绑定 Telegram" : "未绑定 Telegram", systemImage: bound ? "checkmark.circle" : "paperplane")
                    if let detail {
                        if !detail.displayName.isEmpty { LabeledContent("名称", value: detail.displayName).textSelection(.enabled) }
                        if let username = detail.username { LabeledContent("用户名", value: "@" + username).textSelection(.enabled) }
                    }
                    Button(bound ? "在官网管理绑定" : "绑定 Telegram", systemImage: "globe") { showsWebsite = true }
                    if bound { Button("解除绑定", role: .destructive) { confirmsUnbind = true } }
                }
            } else if busy { ProgressView("正在读取绑定信息") }
            if let error { Section { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } } }
            Section { Text("绑定需要 Telegram 官方授权。解除绑定后，Telegram 将不再接收论坛提醒。").font(.footnote).foregroundStyle(.secondary) }
        }
        .seekCanvas().navigationTitle("Telegram 提醒").navigationBarTitleDisplayMode(.inline).disabled(busy)
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $showsWebsite, onDismiss: { Task { await load() } }) {
            WebsiteView(initialURL: URL(string: "https://www.nodeseek.com/setting#contact")!)
        }
        .confirmationDialog("解除 Telegram 绑定？", isPresented: $confirmsUnbind, titleVisibility: .visible) {
            Button("解除绑定", role: .destructive) { Task { await unbind() } }
            Button("取消", role: .cancel) { }
        }
    }

    private func load() async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let status = try await account.website.telegramBinding(userID: userID)
            try Task.checkCancellation()
            detail = status.detail; bound = status.bound
        } catch { if !Task.isCancelled { self.error = SiteError.displayMessage(for: error) } }
    }

    private func unbind() async {
        guard !busy, bound == true else { return }; busy = true; error = nil
        do {
            let _: ReactionResponse = try await account.website.perform(.unbindTelegram, userID: userID)
            detail = nil; bound = nil
            busy = false
            await load()
        } catch { self.error = SiteError.displayMessage(for: error); busy = false }
    }
}
