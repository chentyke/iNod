import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct RulingsView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.openMemberDestination) private var openMember
    let recordID: Int?
    let openDestination: (AppDestination) -> Void

    @State private var loader = ResourceLoader<RulingPage>()
    @State private var query = ""
    @State private var submitted = ""
    @State private var page = 1
    @State private var loadedSearch: String?

    private var directRecordID: Int? {
        guard recordID == nil else { return nil }
        return RulingRecord.parseRecordID(query)
    }

    private var websiteURL: URL {
        if let recordID {
            return URL(string: "https://www.nodeseek.com/ruling#/id-\(recordID)")!
        }
        return NodeSeekRoute.origin.appending(path: "ruling")
    }

    var body: some View {
        ResourceContent(
            loader: loader,
            websiteURL: websiteURL,
            retry: { await load(force: true) }
        ) { data in
            if recordID != nil {
                rulingDetailList(data)
            } else {
                rulingsFeedList(data)
            }
        }
        .navigationTitle(recordID == nil ? "管理记录" : "记录详情")
        .toolbar {
            if recordID != nil, let record = loader.value?.data.first {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: record.shareURL) {
                        Label("分享记录", image: .inkShareRuling)
                    }
                }
            }
        }
        .onChange(of: query) { _, current in
            if recordID == nil, current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !submitted.isEmpty {
                submitted = ""
            }
        }
        .task(id: "\(recordID.map(String.init) ?? "list")|\(submitted)") {
            if loadedSearch != submitted {
                await load()
            }
        }
        .refreshable {
            await load(force: true)
        }
    }

    private func rulingsFeedList(_ data: RulingPage) -> some View {
        List {
            Section {
                CommunitySearchFieldRow(
                    searchIcon: .inkSearchRulings,
                    prompt: "受处理用户名或 #记录编号",
                    text: $query,
                    identifier: "rulings-search-field",
                    submitButtonIdentifier: "rulings-search-submit",
                    onSubmit: submitSearch,
                    onClear: clearSearch
                )
                .listRowInsets(CommunityMetrics.searchRowInsets)
                .listRowBackground(Color.seekCard)
                .listRowSeparator(.hidden)

                if let targetID = directRecordID {
                    NavigationLink(value: AppDestination.rulings(recordID: targetID)) {
                        SettingsRowContent(
                            title: "打开记录 #\(String(targetID))",
                            subtitle: "直接查看该条管理公示的完整详情",
                            symbol: .inkInspectRuling
                        )
                    }
                    .accessibilityIdentifier("rulings-direct-record-\(String(targetID))")
                    .communityRowStyle(alignSeparator: false)
                }
            }

            Section {
                if !submitted.isEmpty {
                    CommunityActiveFilterRow(
                        label: "用户：\(submitted)",
                        identifier: "rulings-active-filter",
                        onClear: clearSearch
                    )
                    .listRowInsets(CommunityMetrics.filterBannerInsets)
                    .listRowBackground(Color.seekCard)
                }

                if data.data.isEmpty {
                    Text(submitted.isEmpty ? "暂无管理记录" : "没有找到与「\(submitted)」相关的管理记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .listRowInsets(CommunityMetrics.rowInsets)
                        .listRowBackground(Color.seekCard)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(data.data) { record in
                        NavigationLink(value: AppDestination.rulings(recordID: record.id)) {
                            RulingListRow(record: record)
                        }
                        .accessibilityIdentifier("ruling-row-\(String(record.id))")
                        .communityRowStyle()
                        .contextMenu {
                            Button("查看记录详情", image: .inkInspectRuling) {
                                openDestination(.rulings(recordID: record.id))
                            }
                            Button("查看 \(record.target_member_name) 主页", image: .inkProfile) {
                                openMember(.profile(record.target_member_id))
                            }
                            Button("查看处理人（\(record.admin_member_name)）主页", image: .inkModerator) {
                                openMember(.profile(record.admin_member_id))
                            }
                            if let location = record.associatedPostLocation {
                                Button(record.associatedTargetTitle, image: record.floor_index == 0 ? .inkReadPost : .inkJumpFloor) {
                                    openDestination(.post(location.post, page: location.page, floor: location.floor))
                                }
                            }
                            ShareLink(item: record.shareURL) { Label("分享记录", image: .inkShareRuling) }
                        }
                    }
                }

                if hasNextPage(data) && loader.error == nil && !loader.isLoadingFirstPage && loadedSearch == submitted {
                    LoadMoreRow(error: loader.nextPageError) {
                        await load(nextPage: true)
                    }
                    .id(page)
                    .listRowBackground(Color.seekCard)
                }
            } header: {
                SeekSectionTitle(
                    title: "处理公示",
                    detail: data.total > 0 ? "共 \(data.total.formatted()) 条" : nil
                )
            }
        }
        .seekGroupedList()
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }

    private func rulingDetailList(_ data: RulingPage) -> some View {
        List {
            if let record = data.data.first {
                Section {
                    ForEach(record.actionItems) { item in
                        HStack(alignment: .top, spacing: CommunityMetrics.rowSpacing) {
                            SeekIconTile(symbol: item.inkIcon)
                            VStack(alignment: .leading, spacing: CommunityMetrics.rowLineSpacing) {
                                Text(item.summary)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.seekInk)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.title)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("ruling-detail-action-\(item.id)")
                        .communityRowStyle()
                    }

                    HStack(spacing: CommunityMetrics.rowSpacing) {
                        SeekIconTile(symbol: .inkClock)
                        Text("处理时间")
                            .foregroundStyle(Color.seekInk)
                        Spacer(minLength: 8)
                        ForumDateText(value: record.created_at)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .communityRowStyle(alignSeparator: false)
                } header: {
                    SeekSectionTitle(title: "处理内容", detail: "#\(String(record.id))")
                }

                Section {
                    NavigationLink(value: MemberDestination.profile(record.target_member_id)) {
                        RulingMemberRow(
                            role: "受处理用户",
                            name: record.target_member_name,
                            memberID: record.target_member_id
                        )
                    }
                    .accessibilityIdentifier("ruling-detail-target")
                    .communityRowStyle()

                    NavigationLink(value: MemberDestination.profile(record.admin_member_id)) {
                        RulingMemberRow(
                            role: "处理版务",
                            name: record.admin_member_name,
                            memberID: record.admin_member_id
                        )
                    }
                    .accessibilityIdentifier("ruling-detail-admin")
                    .communityRowStyle(alignSeparator: record.associatedPostLocation != nil)

                    if let location = record.associatedPostLocation {
                        NavigationLink(value: AppDestination.post(location.post, page: location.page, floor: location.floor)) {
                            SettingsRowContent(
                                title: record.associatedTargetTitle,
                                subtitle: record.floor_index == 0
                                    ? "原帖 #\(String(record.post_id))"
                                    : "原帖 #\(String(record.post_id)) · 定位至第 \(record.floor_index) 楼",
                                symbol: .inkReadPost
                            )
                        }
                        .accessibilityIdentifier("ruling-detail-post")
                        .communityRowStyle(alignSeparator: false)
                    }
                } header: {
                    SeekSectionTitle(title: "关联信息")
                }

                Section {
                    HStack(spacing: CommunityMetrics.rowSpacing) {
                        SeekIconTile(symbol: .inkRulingLink)
                        VStack(alignment: .leading, spacing: CommunityMetrics.rowLineSpacing) {
                            Text("公示链接")
                                .foregroundStyle(Color.seekInk)
                            Text("ruling#/id-\(String(record.id))")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        CommunityCopyCapsule(
                            value: record.shareURL.absoluteString,
                            title: "复制",
                            copiedTitle: "已复制",
                            accessibilityLabelText: "复制管理记录链接",
                            identifier: "ruling-detail-copy-link"
                        )
                    }
                    .frame(minHeight: 44)
                    .communityRowStyle(alignSeparator: false)
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "未找到该管理记录",
                        image: .inkRulings,
                        description: Text(recordID.map { "记录 #\(String($0)) 不存在或已被移除。" } ?? "")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .seekGroupedList()
        .contentMargins(.top, 12, for: .scrollContent)
    }

    private func submitSearch() {
        if let targetID = directRecordID {
            openDestination(.rulings(recordID: targetID))
            return
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if submitted == trimmed {
            Task { await load(force: true) }
        } else {
            submitted = trimmed
        }
    }

    private func clearSearch() {
        query = ""
        submitted = ""
    }

    private func hasNextPage(_ data: RulingPage) -> Bool {
        recordID == nil && page < 100 && page * 20 < data.total
    }

    private func load(force: Bool = false, nextPage: Bool = false) async {
        let search = recordID == nil ? submitted : ""
        if nextPage {
            guard loadedSearch == search, let data = loader.value, hasNextPage(data) else { return }
        }
        let requestedPage = nextPage ? page + 1 : 1
        let force = force || (nextPage && loader.nextPageError != nil)
        let merge = nextPage ? appendPage(\RulingPage.data) : nil
        if await loader.load(
            account.website,
            .rulings(recordID: recordID, page: requestedPage, search: search),
            force: force,
            appending: merge
        ) != nil,
           search == (recordID == nil ? submitted : "") {
            page = requestedPage
            loadedSearch = search
        }
    }
}

private struct RulingListRow: View {
    let record: RulingRecord
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: CommunityMetrics.rowSpacing) {
            SeekIconTile(symbol: record.actionItems.first?.inkIcon ?? .inkRulings)

            VStack(alignment: .leading, spacing: 6) {
                Text(record.description)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.seekInk)
                    .fixedSize(horizontal: false, vertical: true)

                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(record.target_member_name) · #\(String(record.id))")
                        ForumDateText(value: record.created_at)
                        if let postLabel = record.associatedShortLabel {
                            Text(postLabel)
                        }
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 5) {
                        Text(record.target_member_name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text("#\(String(record.id))")
                        Text("·")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        ForumDateText(value: record.created_at)
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                    if let postLabel = record.associatedShortLabel {
                        HStack(spacing: 4) {
                            Image(.inkReadPost)
                                .font(.caption2)
                                .accessibilityHidden(true)
                            Text("\(postLabel) · 处理人 \(record.admin_member_name)")
                                .lineLimit(1)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    } else {
                        Text("处理人 \(record.admin_member_name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minHeight: 44)
    }
}

private struct RulingMemberRow: View {
    let role: String
    let name: String
    let memberID: Int

    private var avatarURL: URL {
        NodeSeekRoute.origin.appending(path: "avatar/\(memberID).png")
    }

    var body: some View {
        HStack(spacing: CommunityMetrics.rowSpacing) {
            AvatarView(name: name, url: avatarURL, size: CommunityMetrics.iconSize)
            VStack(alignment: .leading, spacing: CommunityMetrics.rowLineSpacing) {
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.seekInk)
                Text("\(role) · UID \(String(memberID))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
    }
}
