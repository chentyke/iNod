import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct InvitationsView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var loader = ResourceLoader<InvitationPage>()
    @State private var config: InvitationConfig?
    @State private var page = 1
    @State private var payment: String?
    @State private var confirmsPurchase = false
    var body: some View {
        ResourceContent(loader:loader,websiteURL:NodeSeekRoute.origin.appending(path:"invite"),retry:{ await load(force:true) }) { data in
            List {
                if let config {
                    Section {
                        if config.payment.coin.enabled { purchaseButton("coin",cost:config.payment.coin.cost,balance:account.user?.coins) }
                        if config.payment.stardust.enabled { purchaseButton("stardust",cost:config.payment.stardust.cost,balance:account.user?.stardust) }
                        if !config.payment.coin.enabled && !config.payment.stardust.enabled { Text("官网暂未开放购买。").foregroundStyle(.secondary) }
                    } header: { Text("购买邀请码") } footer: { Text("当前余额：\(account.user?.coins.map(String.init) ?? "—") 鸡腿，\(account.user?.stardust.map(String.init) ?? "—") 星尘。余额足够后可以购买，购买后不能退款。") }
                }
                Section("我的邀请码") {
                    if data.data.isEmpty { ContentUnavailableView("暂无邀请码",systemImage:"ticket") }
                    ForEach(data.data) { item in
                        VStack(alignment:.leading,spacing:10) {
                            HStack { Text(item.code).font(.body.monospaced()).textSelection(.enabled); Spacer(); Text(item.applied ? "已使用" : "未使用").font(.caption).foregroundStyle(item.applied ? Color.secondary : .seekGreen) }
                            HStack { ForumDateText(value:item.created_at).font(.caption).foregroundStyle(.secondary); Spacer(); if !item.applied { ShareLink("分享",item:item.code).font(.subheadline) } }
                        }.padding(.vertical,6)
                    }
                }
                if page * 50 < data.total && loader.error == nil && !loader.isLoadingFirstPage {
                    LoadMoreRow(error: loader.nextPageError, isEnabled: !loader.updating) {
                        await load(nextPage: true)
                    }
                    .id(page)
                }
            }
        }.seekGroupedList().navigationTitle("邀请朋友").task { if loader.value == nil { await load() } }.refreshable { await load(force:true) }
        .confirmationDialog("购买邀请码？",isPresented:$confirmsPurchase,titleVisibility:.visible) {
            Button("消耗 \(cost) 个\(payment == "coin" ? "鸡腿" : "星尘")购买") { Task { await buy() } }; Button("取消",role:.cancel) { payment = nil }
        } message: { Text("购买后不能退款。邀请码分享给他人后，对方可以注册账号。") }
    }
    private var cost: Int { payment == "coin" ? (config?.payment.coin.cost ?? 0) : (config?.payment.stardust.cost ?? 0) }
    private func purchaseButton(_ value: String,cost: Int,balance: Int?) -> some View {
        Button { payment = value; confirmsPurchase = true } label: { LabeledContent(value == "coin" ? "用鸡腿购买" : "用星尘购买",value:"\(cost) 个") }
            .disabled(loader.updating || balance == nil || (balance ?? 0) < cost)
    }
    private func load(force: Bool = false, nextPage: Bool = false) async {
        let store = account.website
        guard !nextPage || page * 50 < (loader.value?.total ?? 0) else { return }
        let requestedPage = nextPage ? page + 1 : 1
        let resource = WebsiteResource.invitations(page: requestedPage)
        let force = force || (nextPage && loader.nextPageError != nil)
        let merge = nextPage ? appendPage(\InvitationPage.data) : nil
        let key = store.key(for: resource)
        if config == nil { config = store.cached(key:store.key(for: .invitationConfig)) }
        let result = await loader.load(key: key, cached: nextPage ? nil : store.cached(key: key), appending: merge) {
            let result: InvitationPage = try await store.load(resource, force: force)
            if !nextPage {
                let freshConfig: InvitationConfig = try await store.load(.invitationConfig, force: force)
                try Task.checkCancellation()
                config = freshConfig
            }
            return result
        }
        if result != nil { page = requestedPage }
    }
    private func buy() async {
        guard !loader.updating,let payment,let config else { return }; loader.updating = true; defer { loader.updating = false }
        do {
            let fresh: InvitationConfig = try await account.website.load(.invitationConfig, force: true)
            guard (payment == "coin" ? fresh.payment.coin.cost == config.payment.coin.cost : fresh.payment.stardust.cost == config.payment.stardust.cost) else { self.config = fresh; throw SiteError.message("官网价格已变化，请确认新价格后再购买。") }
            let _: ReactionResponse = try await account.website.perform(.buyInvitation(payment: payment), userID: userID)
            await load(force:true); await account.refresh(force:true)
        } catch { loader.error = LoadFailure(error) }
    }
}
