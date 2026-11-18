import NodeSeekCore
import NodeSeekClient
import SwiftUI

private struct TelegramBindingSnapshot: Decodable {
    let bound: Bool
    let detail: TelegramAccount?
}

struct TelegramSettingsView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    let userID: Int

    @State private var snapshot: TelegramBindingSnapshot?
    @State private var failure: LoadFailure?
    @State private var isLoading = false
    @State private var isUnbinding = false
    @State private var confirmsUnbind = false
    /// Set when the reader leaves for the website, so the binding is read again when they come back.
    @State private var awaitsWebsite = false

    private var isBusy: Bool {
        isLoading || isUnbinding
    }

    var body: some View {
        AccountDataView(
            value: snapshot,
            error: failure,
            isBusy: isBusy,
            retry: { await load() }
        ) { data in
            List {
                Section {
                    VStack(alignment: .leading, spacing: AccountSettingsMetrics.blockSpacing) {
                        let headerLayout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                            : AnyLayout(HStackLayout(alignment: .center, spacing: AccountSettingsMetrics.rowSpacing))
                        headerLayout {
                            HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                                SeekIconTile(
                                    symbol: data.bound ? "paperplane.fill" : "paperplane",
                                    tint: data.bound ? .seekGreen : .seekInk
                                )
                                Text(data.bound ? "已绑定 Telegram" : "未绑定 Telegram")
                                    .font(.headline)
                                    .foregroundStyle(Color.seekInk)
                            }
                            if !typeSize.isAccessibilitySize {
                                Spacer(minLength: 8)
                            }
                            SettingsStatusPill(
                                text: data.bound ? "已绑定" : "未绑定",
                                active: data.bound
                            )
                        }

                        Text("绑定后可通过 Telegram 机器人接收私信、回复与 @提及 的论坛提醒。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        SettingsActionPill(
                            title: data.bound ? "前往官网管理绑定" : "前往官网绑定 Telegram",
                            symbol: "arrow.up.right",
                            primary: !data.bound,
                            surface: .seekTray
                        ) {
                            awaitsWebsite = true
                            Browser.open(NodeSeekRoute.settings(section: "contact").url)
                        }
                        .disabled(isBusy)
                        .accessibilityIdentifier("telegram-website-button")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("telegram-status-card")
                    .listRowInsets(AccountSettingsMetrics.shapeCardInsets)
                    .listRowBackground(Color.seekCard)
                    .listRowSeparator(.hidden)
                }

                if data.bound {
                    if let detail = data.detail, (!detail.displayName.isEmpty || detail.username != nil) {
                        Section {
                            if !detail.displayName.isEmpty {
                                LabeledContent("名称") {
                                    Text(detail.displayName)
                                        .foregroundStyle(Color.seekInk)
                                        .textSelection(.enabled)
                                }
                                .frame(minHeight: 36)
                                .accessibilityIdentifier("telegram-name-row")
                                .listRowBackground(Color.seekCard)
                            }
                            if let username = detail.username, !username.isEmpty {
                                LabeledContent("用户名") {
                                    Text("@" + username)
                                        .font(.body.monospaced())
                                        .foregroundStyle(Color.seekInk)
                                        .textSelection(.enabled)
                                }
                                .frame(minHeight: 36)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("telegram-username-row")
                                .listRowBackground(Color.seekCard)
                            }
                        } header: {
                            SeekSectionTitle(title: "绑定账号")
                        }
                    }

                    Section {
                        SettingsActionPill(
                            title: "解除绑定",
                            symbol: "link.badge.plus",
                            busyTitle: "正在解绑…",
                            isBusy: isUnbinding,
                            primary: false,
                            destructive: true,
                            surface: .seekCard
                        ) {
                            confirmsUnbind = true
                        }
                        .disabled(isBusy)
                        .accessibilityIdentifier("telegram-unbind-button")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } footer: {
                        Text("绑定需通过官网完成 Telegram 官方授权；解除绑定后将不再接收推送提醒。")
                    }
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
        }
        .navigationTitle("Telegram 提醒")
        .interactiveDismissDisabled(isUnbinding)
        .task {
            if snapshot == nil {
                await load()
            }
        }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, awaitsWebsite else { return }
            awaitsWebsite = false
            Task { await load() }
        }
        .alert(
            "解除 Telegram 绑定？",
            isPresented: $confirmsUnbind
        ) {
            Button("解除绑定", role: .destructive) {
                Task { await unbind() }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("解除绑定后，Telegram 将不再接收论坛提醒。")
        }
    }

    private func load() async {
        guard !isBusy else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let status = try await account.website.telegramBinding(userID: userID)
            try Task.checkCancellation()
            snapshot = TelegramBindingSnapshot(bound: status.bound, detail: status.detail)
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled {
                failure = LoadFailure(error)
            }
        }
    }

    private func unbind() async {
        guard !isBusy, snapshot?.bound == true else { return }
        isUnbinding = true
        failure = nil
        do {
            let _: ReactionResponse = try await account.website.perform(.unbindTelegram, userID: userID)
            isUnbinding = false
            await load()
        } catch {
            isUnbinding = false
            failure = LoadFailure(error)
        }
    }
}
