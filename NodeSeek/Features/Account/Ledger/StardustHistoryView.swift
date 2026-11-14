import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct StardustHistoryView: View {
    let memberID: Int
    var initialReference = ""
    @Environment(AccountSession.self) private var account
    @State private var loader = ResourceLoader<StardustRecords>()
    @State private var type = ""
    @State private var reference = ""
    @State private var peer = ""
    @State private var appliedType = ""
    @State private var appliedReference = ""
    @State private var appliedPeer = ""
    @State private var page = 1
    @State private var lastCursor: Int?
    @State private var showsFilter = false
    @State private var filterRevision = 0
    @State private var loadedFilterRevision: Int?
    var body: some View {
        ResourceContent(loader:loader,retry:{ await load(force:true) }) { data in
            List {
                if memberID == account.user?.id { Section { LabeledContent("当前星尘",value:(account.user?.stardust ?? 0).formatted()) } }
                Section("收支记录") {
                    if data.records.isEmpty { ContentUnavailableView("暂无记录",systemImage:"list.bullet.rectangle") }
                    ForEach(data.records) { record in
                        VStack(alignment:.leading,spacing:10) {
                            HStack { Text(title(record.type)).font(.subheadline.weight(.medium)); Spacer(); Text("\(record.diff > 0 ? "+" : "")\(record.diff)").font(.headline.monospacedDigit()).foregroundStyle(record.diff > 0 ? Color.seekGreen : .primary) }
                            HStack { ForumDateText(value:record.created_at); Spacer(); Text("余额 \(record.result)") }.font(.caption).foregroundStyle(.secondary)
                            if let peer = record.peer_id { NavigationLink("对方 UID \(peer)",value:MemberDestination.profile(peer)).font(.caption) }
                            if let ref = record.ref_id { Text("Ref ID \(ref)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        }.padding(.vertical,8)
                    }
                    if hasNextPage(data) && loader.error == nil && !loader.isLoadingFirstPage && loadedFilterRevision == filterRevision {
                        LoadMoreRow(error: loader.nextPageError, isEnabled: !showsFilter) {
                            await load(nextPage: true)
                        }
                        .id(page)
                    }
                }
            }
        }.seekGroupedList().navigationTitle("星尘明细")
        .task(id: filterRevision) {
            guard loadedFilterRevision != filterRevision else { return }
            if filterRevision == 0 && !initialReference.isEmpty {
                reference = initialReference
                appliedReference = initialReference
            }
            await load()
        }
        .refreshable { await load(force:true) }
        .toolbar {
            Button("筛选",systemImage:"line.3.horizontal.decrease") { showsFilter = true }
            if account.user?.id == memberID { NavigationLink { StardustTransferView(userID:memberID) } label: { Label("转账",systemImage:"paperplane") } }
        }
        .sheet(isPresented:$showsFilter) {
            NavigationStack {
                Form {
                    Picker("类型",selection:$type) { Text("全部").tag(""); ForEach(["system","admin","transfer","upvote","buyCode"],id:\.self) { Text(title($0)).tag($0) } }
                    TextField("对方 UID",text:$peer).keyboardType(.numberPad)
                    TextField("Ref ID",text:$reference).keyboardType(.numberPad)
                    Button("清除筛选") { type = ""; peer = ""; reference = "" }
                }.scrollEdgeEffectStyle(.soft, for: .top)
                .navigationTitle("筛选记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("应用", action: applyFilters).disabled((!peer.isEmpty && Int(peer) == nil) || (!reference.isEmpty && Int(reference) == nil)) }
            }.presentationDetents([.medium,.large])
        }
    }
    private func title(_ value: String) -> String { ["system":"系统","admin":"管理","transfer":"转账","upvote":"点赞","buyCode":"购买邀请码"][value] ?? value }
    private func applyFilters() {
        appliedType = type
        appliedReference = reference
        appliedPeer = peer
        filterRevision += 1
        showsFilter = false
    }

    private func hasNextPage(_ data: StardustRecords) -> Bool {
        data.exist_more == true && data.cursor != nil && data.cursor != lastCursor
    }

    private func load(force: Bool = false, nextPage: Bool = false) async {
        let revision = filterRevision
        if nextPage {
            guard loadedFilterRevision == revision, let data = loader.value, hasNextPage(data) else { return }
        }
        let requestedPage = nextPage ? page + 1 : 1
        let cursor = nextPage ? loader.value?.cursor : nil
        let force = force || (nextPage && loader.nextPageError != nil)
        let merge = nextPage ? appendPage(\StardustRecords.records) : nil
        if await loader.load(account.website, .stardust(memberID: memberID, type: appliedType, reference: appliedReference, peer: appliedPeer, beforeID: cursor), force: force, appending: merge) != nil,
           filterRevision == revision {
            page = requestedPage
            lastCursor = cursor
            loadedFilterRevision = revision
        }
    }
}
