import NodeSeekCore
import NodeSeekClient
import SwiftUI
import UIKit

struct LuckyView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.openAppDestination) private var openDestination
    @Environment(\.openMemberDestination) private var openMember
    @Environment(\.dynamicTypeSize) private var typeSize
    var initial: LuckyDraw?

    private enum Field: Hashable {
        case post, count, floor
    }

    @State private var post = ""
    @State private var revealTime = Date.now.addingTimeInterval(3600)
    @State private var count = "1"
    @State private var floor = "1"
    @State private var removeDuplicates = true
    @State private var winners: [LuckyFloor]?
    @State private var drawnFor: LuckyDraw?
    @State private var error: String?
    @State private var notice: String?
    @State private var busy = false
    @FocusState private var focusedField: Field?

    private var parsedInput: LuckyDraw.ParsedInput? {
        LuckyDraw.parseInput(post)
    }

    private var pendingImportedDraw: LuckyDraw? {
        if case .draw(let imported) = parsedInput {
            return imported
        }
        return nil
    }

    private var draw: LuckyDraw? {
        if let pendingImportedDraw {
            return pendingImportedDraw
        }
        guard case .post(let address) = parsedInput,
              let winnerCount = Int(count.trimmingCharacters(in: .whitespacesAndNewlines)),
              let firstFloor = Int(floor.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let candidate = LuckyDraw(
            postID: address.id,
            revealTime: revealTime,
            count: winnerCount,
            firstFloor: firstFloor,
            removeDuplicates: removeDuplicates
        )
        return candidate.valid ? candidate : nil
    }

    private var validationMessage: String? {
        LuckyDraw.validationMessage(postInput: post, countInput: count, firstFloorInput: floor)
    }

    var body: some View {
        List {
            Section {
                postInputRow
                    .communityRowStyle()

                if let imported = pendingImportedDraw {
                    Button {
                        focusedField = nil
                        apply(imported, message: "已将开奖链接中的参数填入表单。")
                    } label: {
                        HStack(spacing: CommunityMetrics.rowSpacing) {
                            SeekIconTile(symbol: .inkDrawPostLink)
                            VStack(alignment: .leading, spacing: CommunityMetrics.rowLineSpacing) {
                                Text("识别到完整开奖链接")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.seekInk)
                                Text("帖子 #\(String(imported.postID)) · 抽取 \(imported.count) 人 · 点击填入下方各项")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            SettingsStatusPill(text: "填入", active: true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.seekRow)
                    .accessibilityIdentifier("lucky-apply-link-button")
                    .communityRowStyle()
                }

                revealTimeRow
                    .communityRowStyle()

                numberFieldRow(
                    title: "中奖人数",
                    symbol: .inkWinners,
                    text: $count,
                    field: .count,
                    unit: "人",
                    identifier: "lucky-count-field"
                )
                .communityRowStyle()

                numberFieldRow(
                    title: "起始楼层",
                    symbol: .inkStartFloor,
                    text: $floor,
                    field: .floor,
                    unit: "楼起",
                    identifier: "lucky-floor-field"
                )
                .communityRowStyle()

                Toggle(isOn: $removeDuplicates) {
                    SettingsRowContent(
                        title: "每位用户只参与一次",
                        subtitle: "同一用户多次回帖时仅保留最早楼层",
                        symbol: .inkUniqueMember
                    )
                }
                .tint(Color.seekGreen)
                .accessibilityIdentifier("lucky-dedupe-toggle")
                .communityRowStyle(alignSeparator: false)
            } header: {
                SeekSectionTitle(title: "抽奖设置")
            } footer: {
                Text("结果由指定帖子的楼层数据与 drand 公开随机数共同决定，算法与 NodeSeek 官网一致。")
            }

            if let validationMessage {
                Section {
                    SettingsFeedbackRow(message: validationMessage, isSuccess: false)
                        .listRowInsets(CommunityMetrics.rowInsets)
                        .listRowBackground(Color.seekCard)
                        .listRowSeparator(.hidden)
                }
            }

            if let draw {
                drawActionSection(draw)
            }

            if let notice {
                Section {
                    SettingsFeedbackRow(message: notice, isSuccess: true)
                        .listRowInsets(CommunityMetrics.rowInsets)
                        .listRowBackground(Color.seekCard)
                        .listRowSeparator(.hidden)
                }
            }

            if let error {
                Section {
                    SettingsFeedbackRow(message: error, isSuccess: false)
                        .listRowInsets(CommunityMetrics.rowInsets)
                        .listRowBackground(Color.seekCard)
                        .listRowSeparator(.hidden)
                }
            }

            if let winners {
                winnersSection(winners)
            }
        }
        .seekGroupedList()
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("抽奖工具")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if let initial {
                apply(initial)
                await load(initial)
            }
        }
    }

    private var postInputRow: some View {
        HStack(spacing: CommunityMetrics.rowSpacing) {
            SeekIconTile(symbol: .inkDrawTarget)
            VStack(alignment: .leading, spacing: 2) {
                Text("目标帖子或开奖链接")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("帖子编号、帖子链接或 lucky 链接", text: $post)
                    .focused($focusedField, equals: .post)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        focusedField = nil
                        if let imported = pendingImportedDraw {
                            apply(imported, message: "已从开奖链接导入抽奖参数。")
                        }
                    }
                    .accessibilityIdentifier("lucky-post-field")
            }

            if !post.isEmpty {
                Button {
                    post = ""
                    winners = nil
                    drawnFor = nil
                    error = nil
                    notice = nil
                } label: {
                    Image(.inkClearInput)
                        .foregroundStyle(Color.seekButtonIcon)
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空输入")
                .accessibilityIdentifier("lucky-post-clear")
            }
        }
        .frame(minHeight: 44)
    }

    private var revealTimeRow: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: CommunityMetrics.rowSpacing) {
                        SeekIconTile(symbol: .inkDrawTime)
                        Text("开奖时间")
                            .foregroundStyle(Color.seekInk)
                    }
                    DatePicker("开奖时间", selection: $revealTime)
                        .labelsHidden()
                }
            } else {
                HStack(spacing: CommunityMetrics.rowSpacing) {
                    SeekIconTile(symbol: .inkDrawTime)
                    DatePicker("开奖时间", selection: $revealTime)
                        .foregroundStyle(Color.seekInk)
                }
            }
        }
        .frame(minHeight: 44)
    }

    private func numberFieldRow(
        title: String,
        symbol: ImageResource,
        text: Binding<String>,
        field: Field,
        unit: String,
        identifier: String
    ) -> some View {
        HStack(spacing: CommunityMetrics.rowSpacing) {
            SeekIconTile(symbol: symbol)
            Text(title)
                .foregroundStyle(Color.seekInk)
            Spacer(minLength: 8)
            TextField("1", text: text)
                .focused($focusedField, equals: field)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.seekInk)
                .frame(minWidth: 44, maxWidth: 88)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(title)
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }

    private func drawActionSection(_ currentDraw: LuckyDraw) -> some View {
        let ready = currentDraw.isReadyToReveal()
        return Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 8) {
                    Text("帖子 #\(String(currentDraw.postID))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.seekInk)
                    Spacer(minLength: 8)
                    SettingsStatusPill(
                        text: ready ? "可开奖" : "待开奖",
                        active: ready
                    )
                }

                Text("公开随机数第 \(String(currentDraw.round)) 轮 · 抽取 \(currentDraw.count) 人 · \(currentDraw.firstFloor) 楼起\(currentDraw.removeDuplicates ? " · 去重" : "")")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    SettingsActionPill(
                        title: "查看开奖结果",
                        symbol: .inkDrawResult,
                        busyTitle: "正在开奖…",
                        isBusy: busy,
                        primary: true,
                        fullWidth: true
                    ) {
                        focusedField = nil
                        if let imported = pendingImportedDraw {
                            apply(imported)
                        }
                        Task { await load(currentDraw) }
                    }
                    .accessibilityIdentifier("lucky-reveal-button")

                    Menu {
                        ShareLink(item: currentDraw.url) { Label("分享开奖链接", image: .inkShareDraw) }
                        ShareLink(item: currentDraw.markdownLink) { Label("分享 Markdown 链接", image: .inkShareDrawLink) }
                        Button("复制 Markdown 链接", image: .inkCopyDraw) {
                            UIPasteboard.general.string = currentDraw.markdownLink
                            notice = "已复制 Markdown 开奖链接。"
                            error = nil
                        }
                        if let address = PostAddress(String(currentDraw.postID)) {
                            Button("查看目标帖子", image: .inkReadPost) {
                                openDestination(.post(address.summary, page: 1, floor: nil))
                            }
                        }
                    } label: {
                        Image(.inkShareDraw)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.seekButtonIcon)
                            .frame(width: 48, height: 48)
                            .background(Color.seekTray, in: .capsule)
                    }
                    .accessibilityLabel("分享或查看原帖")
                    .accessibilityIdentifier("lucky-share-menu")
                }
            }
            .padding(.vertical, 6)
            .listRowInsets(CommunityMetrics.rowInsets)
            .listRowBackground(Color.seekCard)
            .listRowSeparator(.hidden)
        } header: {
            SeekSectionTitle(title: "开奖与链接")
        }
    }

    private func winnersSection(_ items: [LuckyFloor]) -> some View {
        let activeDraw = drawnFor ?? draw
        return Section {
            if items.isEmpty {
                Text("没有符合条件的参与楼层")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .listRowInsets(CommunityMetrics.rowInsets)
                    .listRowBackground(Color.seekCard)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(items) { winner in
                    NavigationLink(value: MemberDestination.profile(winner.member_id)) {
                        LuckyWinnerRow(winner: winner)
                    }
                    .accessibilityIdentifier("lucky-winner-\(String(winner.floor_id))")
                    .communityRowStyle()
                    .contextMenu {
                        Button("查看个人主页", image: .inkProfile) {
                            openMember(.profile(winner.member_id))
                        }
                        if let activeDraw, let address = PostAddress(String(activeDraw.postID)) {
                            Button("跳转到 #\(String(winner.floor_id)) 楼", image: .inkJumpFloor) {
                                openDestination(.post(
                                    address.summary,
                                    page: PostAddress.page(forFloor: winner.floor_id),
                                    floor: winner.floor_id
                                ))
                            }
                        }
                    }
                }

                if let activeDraw {
                    let announcement = activeDraw.winnersAnnouncement(items)
                    HStack(spacing: CommunityMetrics.rowSpacing) {
                        SeekIconTile(symbol: .inkDrawNotice)
                        VStack(alignment: .leading, spacing: CommunityMetrics.rowLineSpacing) {
                            Text("中奖通知文案")
                                .foregroundStyle(Color.seekInk)
                            Text("包含 @中奖用户 与对应楼层直达链接")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        CommunityCopyCapsule(
                            value: announcement,
                            title: "复制",
                            copiedTitle: "已复制",
                            accessibilityLabelText: "复制中奖通知文案",
                            identifier: "lucky-copy-winners"
                        )
                    }
                    .frame(minHeight: 44)
                    .contextMenu {
                        ShareLink(item: announcement) { Label("分享中奖名单", image: .inkShareWinners) }
                    }
                    .communityRowStyle(alignSeparator: false)
                }
            }
        } header: {
            SeekSectionTitle(
                title: "开奖结果",
                detail: items.isEmpty ? nil : "\(items.count) 人中奖"
            )
        }
    }

    private func apply(_ target: LuckyDraw, message: String? = nil) {
        post = String(target.postID)
        revealTime = target.revealTime
        count = String(target.count)
        floor = String(target.firstFloor)
        removeDuplicates = target.removeDuplicates
        winners = nil
        drawnFor = nil
        error = nil
        notice = message
    }

    private func load(_ target: LuckyDraw) async {
        guard !busy else { return }
        notice = nil
        guard target.isReadyToReveal() else {
            error = "还没到开奖时间（\(target.revealTime.formatted(date: .abbreviated, time: .shortened))），可先通过右侧按钮分享开奖链接。"
            return
        }
        busy = true
        error = nil
        winners = nil
        defer { busy = false }
        do {
            let result = try await account.website.drawWinners(target)
            try Task.checkCancellation()
            drawnFor = target
            winners = result
        } catch {
            if !Task.isCancelled {
                self.error = SiteError.displayMessage(for: error)
            }
        }
    }
}

private struct LuckyWinnerRow: View {
    let winner: LuckyFloor
    @Environment(\.dynamicTypeSize) private var typeSize

    private var avatarURL: URL {
        NodeSeekRoute.origin.appending(path: "avatar/\(winner.member_id).png")
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: CommunityMetrics.rowSpacing) {
                        AvatarView(name: winner.member_name, url: avatarURL, size: CommunityMetrics.iconSize)
                        identityStack
                    }
                    floorPill
                }
            } else {
                HStack(spacing: CommunityMetrics.rowSpacing) {
                    AvatarView(name: winner.member_name, url: avatarURL, size: CommunityMetrics.iconSize)
                    identityStack
                    Spacer(minLength: 8)
                    floorPill
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var identityStack: some View {
        VStack(alignment: .leading, spacing: CommunityMetrics.rowLineSpacing) {
            Text(winner.member_name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.seekInk)
            Text("UID \(String(winner.member_id))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var floorPill: some View {
        Text("#\(String(winner.floor_id))")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(Color.seekInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.seekTray, in: .capsule)
            .fixedSize()
    }
}
