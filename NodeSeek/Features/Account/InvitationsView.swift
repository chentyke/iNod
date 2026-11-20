import NodeSeekCore
import NodeSeekClient
import SwiftUI
import UIKit

private struct LoadedInvitations: Decodable {
    var page: InvitationPage
    var config: InvitationConfig
}

struct InvitationsView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var loader = ResourceLoader<LoadedInvitations>()
    @State private var page = 1
    @State private var pendingPayment: String?
    @State private var purchasingPayment: String?
    @State private var purchaseNotice: (message: String, isSuccess: Bool)?

    private var currentConfig: InvitationConfig? {
        loader.value?.config
    }

    private var pendingCost: Int {
        guard let config = currentConfig, let pendingPayment else { return 0 }
        return pendingPayment == "coin" ? config.payment.coin.cost : config.payment.stardust.cost
    }

    private var pendingUnit: String {
        pendingPayment == "coin" ? "鸡腿" : "星尘"
    }

    var body: some View {
        ResourceContent(
            loader: loader,
            websiteURL: NodeSeekRoute.origin.appending(path: "invite"),
            retry: { await load(force: true) }
        ) { loaded in
            let data = loaded.page
            List {
                purchaseSection(loaded.config)

                if let purchaseNotice {
                    Section {
                        SettingsFeedbackRow(
                            message: purchaseNotice.message,
                            isSuccess: purchaseNotice.isSuccess
                        )
                        .listRowInsets(CommunityMetrics.rowInsets)
                        .listRowBackground(Color.seekCard)
                        .listRowSeparator(.hidden)
                    }
                }

                Section {
                    if data.data.isEmpty {
                        Text("暂无邀请码，在上方兑换后会显示在这里")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .listRowInsets(CommunityMetrics.rowInsets)
                            .listRowBackground(Color.seekCard)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(data.data) { item in
                            InvitationCodeRow(item: item)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("invitation-row-\(item.code)")
                                .communityRowStyle()
                                .contextMenu {
                                    Button("复制邀请码", image: .inkCopyInvite) {
                                        UIPasteboard.general.string = item.code
                                    }
                                    if !item.applied {
                                        ShareLink(item: item.code) { Label("分享邀请码", image: .inkShareInvite) }
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !item.applied {
                                        ShareLink(item: item.code) {
                                            Label("分享", image: .inkShareInvite)
                                        }
                                        .tint(.seekGreen)
                                    }
                                }
                        }
                    }

                    if page * 50 < data.total && loader.error == nil && !loader.isLoadingFirstPage {
                        LoadMoreRow(error: loader.nextPageError, isEnabled: !loader.updating) {
                            await load(nextPage: true)
                        }
                        .id(page)
                        .listRowBackground(Color.seekCard)
                    }
                } header: {
                    SeekSectionTitle(
                        title: "我的邀请码",
                        detail: codesSummaryDetail(for: data)
                    )
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
        }
        .navigationTitle("邀请朋友")
        .task {
            if loader.value == nil {
                await load()
            }
        }
        .refreshable {
            await load(force: true)
        }
        .alert(
            "兑换邀请码？",
            isPresented: Binding(
                get: { pendingPayment != nil },
                set: { if !$0 { pendingPayment = nil } }
            )
        ) {
            if let method = pendingPayment {
                Button("消耗 \(pendingCost.formatted()) \(pendingUnit)兑换") {
                    pendingPayment = nil
                    Task { await buy(payment: method) }
                }
            }
            Button("取消", role: .cancel) {
                pendingPayment = nil
            }
        } message: {
            Text("兑换后不可退还\(pendingUnit)。生成的邀请码可发送给朋友注册 NodeSeek 账号。")
        }
    }

    private func purchaseSection(_ config: InvitationConfig) -> some View {
        let hasCoin = config.payment.coin.enabled
        let hasStardust = config.payment.stardust.enabled

        return Section {
            if hasCoin {
                InvitationPurchaseRow(
                    title: "用鸡腿兑换",
                    unit: "鸡腿",
                    symbol: .inkRedeemChickenInvite,
                    tint: .orange,
                    option: config.payment.coin,
                    balance: account.user?.coins,
                    isBusy: purchasingPayment == "coin",
                    isDisabled: loader.updating || !config.payment.coin.canAfford(with: account.user?.coins),
                    identifier: "invitation-buy-coin"
                ) {
                    pendingPayment = "coin"
                }
                .communityRowStyle(alignSeparator: hasStardust)
            }

            if hasStardust {
                InvitationPurchaseRow(
                    title: "用星尘兑换",
                    unit: "星尘",
                    symbol: .inkRedeemDustInvite,
                    tint: .indigo,
                    option: config.payment.stardust,
                    balance: account.user?.stardust,
                    isBusy: purchasingPayment == "stardust",
                    isDisabled: loader.updating || !config.payment.stardust.canAfford(with: account.user?.stardust),
                    identifier: "invitation-buy-stardust"
                ) {
                    pendingPayment = "stardust"
                }
                .communityRowStyle(alignSeparator: false)
            }

            if !hasCoin && !hasStardust {
                SettingsRowContent(
                    title: "暂未开放兑换",
                    subtitle: "官网当前关闭了邀请码购买通道",
                    symbol: .inkInviteExpiry
                )
                .communityRowStyle(alignSeparator: false)
            }
        } header: {
            SeekSectionTitle(title: "兑换邀请码")
        } footer: {
            Text("兑换后不可退款。邀请码使用一次后自动失效。")
        }
    }

    private func codesSummaryDetail(for pageData: InvitationPage) -> String? {
        guard pageData.total > 0 else { return nil }
        let available = pageData.availableCount
        if available > 0 {
            return "\(available) 个可用 · 共 \(pageData.total.formatted()) 个"
        }
        return "共 \(pageData.total.formatted()) 个"
    }

    private func load(force: Bool = false, nextPage: Bool = false) async {
        let store = account.website
        guard !nextPage || page * 50 < (loader.value?.page.total ?? 0) else { return }
        let requestedPage = nextPage ? page + 1 : 1
        let resource = WebsiteResource.invitations(page: requestedPage)
        let force = force || (nextPage && loader.nextPageError != nil)
        let key = store.key(for: resource)
        let cached: LoadedInvitations? = if !nextPage,
                                            let cachedPage: InvitationPage = store.cached(key: key),
                                            let cachedConfig: InvitationConfig = store.cached(key: store.key(for: .invitationConfig)) {
            LoadedInvitations(page: cachedPage, config: cachedConfig)
        } else {
            nil
        }
        let merge: ((LoadedInvitations, LoadedInvitations) -> LoadedInvitations)? = nextPage
            ? { previous, incoming in
                var merged = previous
                merged.page = appendPage(\InvitationPage.data)(previous.page, incoming.page)
                merged.config = incoming.config
                return merged
            }
            : nil

        let result = await loader.load(key: key, cached: cached, appending: merge) {
            let loadedPage: InvitationPage = try await store.load(resource, force: force)
            if nextPage, let existingConfig = loader.value?.config {
                return LoadedInvitations(page: loadedPage, config: existingConfig)
            }
            let loadedConfig: InvitationConfig = try await store.load(.invitationConfig, force: force)
            return LoadedInvitations(page: loadedPage, config: loadedConfig)
        }
        if result != nil {
            page = requestedPage
        }
    }

    private func buy(payment: String) async {
        guard !loader.updating, let config = currentConfig else { return }
        loader.updating = true
        purchasingPayment = payment
        purchaseNotice = nil
        defer {
            loader.updating = false
            purchasingPayment = nil
        }
        do {
            let fresh: InvitationConfig = try await account.website.load(.invitationConfig, force: true)
            let samePrice = payment == "coin"
                ? fresh.payment.coin.cost == config.payment.coin.cost && fresh.payment.coin.enabled
                : fresh.payment.stardust.cost == config.payment.stardust.cost && fresh.payment.stardust.enabled
            guard samePrice else {
                loader.value?.config = fresh
                throw SiteError.message("官网兑换条件已变化，请确认最新价格后再试。")
            }
            let _: ReactionResponse = try await account.website.perform(.buyInvitation(payment: payment), userID: userID)
            await load(force: true)
            await account.refresh(force: true)
            purchaseNotice = ("已成功兑换新的邀请码。", true)
        } catch is CancellationError {
        } catch {
            purchaseNotice = (SiteError.displayMessage(for: error), false)
        }
    }
}

private struct InvitationPurchaseRow: View {
    let title: String
    let unit: String
    let symbol: ImageResource
    let tint: Color
    let option: InvitationConfig.Option
    let balance: Int?
    let isBusy: Bool
    let isDisabled: Bool
    let identifier: String
    let onTap: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var subtitle: String {
        let price = "需 \(option.cost.formatted()) \(unit)"
        if let shortfall = option.shortfall(for: balance) {
            return "\(price) · 还差 \(shortfall.formatted()) \(unit)"
        }
        if let balance {
            return "\(price) · 余额 \(balance.formatted())"
        }
        return "\(price) · 余额未知"
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: CommunityMetrics.rowSpacing) {
                        SeekIconTile(symbol: symbol, tint: tint)
                        labelStack
                    }
                    actionButton(fullWidth: true)
                }
            } else {
                HStack(spacing: CommunityMetrics.rowSpacing) {
                    SeekIconTile(symbol: symbol, tint: tint)
                    labelStack
                    Spacer(minLength: 8)
                    actionButton(fullWidth: false)
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var labelStack: some View {
        VStack(alignment: .leading, spacing: CommunityMetrics.rowLineSpacing) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.seekInk)
            Text(subtitle)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionButton(fullWidth: Bool) -> some View {
        SettingsActionPill(
            title: "兑换",
            busyTitle: "兑换中…",
            isBusy: isBusy,
            primary: true,
            fullWidth: fullWidth
        ) {
            onTap()
        }
        .disabled(isDisabled)
        .accessibilityIdentifier(identifier)
    }
}

private struct InvitationCodeRow: View {
    let item: Invitation
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: CommunityMetrics.rowSpacing) {
                        iconTile
                        Text(item.code)
                            .font(.body.weight(.semibold).monospaced())
                            .foregroundStyle(item.applied ? .secondary : Color.seekInk)
                            .textSelection(.enabled)
                    }
                    HStack(spacing: 8) {
                        statusPill
                        dateLabel
                    }
                    if !item.applied {
                        copyButton
                    }
                }
            } else {
                HStack(alignment: .center, spacing: CommunityMetrics.rowSpacing) {
                    iconTile
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(item.code)
                                .font(.body.weight(.semibold).monospaced())
                                .foregroundStyle(item.applied ? .secondary : Color.seekInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            statusPill
                        }
                        HStack(alignment: .center, spacing: 8) {
                            dateLabel
                            Spacer(minLength: 8)
                            if !item.applied {
                                copyButton
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var iconTile: some View {
        SeekIconTile(
            symbol: item.applied ? .inkUsedInvite : .inkInvite,
            tint: item.applied ? .secondary : .seekGreen
        )
    }

    private var statusPill: some View {
        SettingsStatusPill(
            text: item.applied ? "已使用" : "可使用",
            active: !item.applied
        )
    }

    private var dateLabel: some View {
        ForumDateText(value: item.created_at)
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var copyButton: some View {
        CommunityCopyCapsule(
            value: item.code,
            title: "复制",
            copiedTitle: "已复制",
            accessibilityLabelText: "复制邀请码 \(item.code)",
            identifier: "invitation-copy-\(item.code)"
        )
    }
}
