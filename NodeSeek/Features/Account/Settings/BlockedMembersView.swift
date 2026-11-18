import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct BlockedMembersView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.openMemberDestination) private var openMember
    @Environment(\.dynamicTypeSize) private var typeSize
    let userID: Int
    @State private var loader = AccountLoader<AccountPage<BlockedMember>>()
    @State private var name = ""
    @State private var pendingUnblock: BlockedMember?
    @State private var isAdding = false
    @State private var removingID: Int?

    private var normalizedInput: String? {
        BlockedMember.normalizedUsername(name)
    }

    private var isDuplicateInput: Bool {
        guard let candidate = normalizedInput?.lowercased(),
              let items = loader.value?.items else { return false }
        return items.contains { $0.name.lowercased() == candidate }
    }

    private var canAdd: Bool {
        normalizedInput != nil && !isDuplicateInput && !loader.isUpdating
    }

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { data in
            List {
                Section {
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 12) {
                                inputFieldRow
                                addButton(fullWidth: true)
                            }
                        } else {
                            HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                                inputFieldRow
                                addButton(fullWidth: false)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .settingsRowStyle(alignSeparator: false)
                } header: {
                    SeekSectionTitle(title: "添加屏蔽")
                } footer: {
                    if isDuplicateInput {
                        Text("该用户已在屏蔽名单中。")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("屏蔽后，对方的主题和回复默认隐藏，可在上一页切换是否显示。")
                    }
                }

                Section {
                    if data.items.isEmpty {
                        Text("当前没有屏蔽任何用户")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.seekCard)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(data.items) { member in
                        BlockedMemberRow(
                            member: member,
                            isRemoving: removingID == member.id,
                            isDisabled: loader.isUpdating
                        ) {
                            pendingUnblock = member
                        }
                        .contextMenu {
                            Button("查看个人主页", systemImage: "person.crop.circle") {
                                openMember(.profile(member.id))
                            }
                            Button("解除屏蔽", systemImage: "person.badge.plus") {
                                pendingUnblock = member
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("解除") {
                                pendingUnblock = member
                            }
                            .disabled(loader.isUpdating)
                        }
                        .settingsRowStyle()
                    }
                } header: {
                    SeekSectionTitle(
                        title: "已屏蔽名单",
                        detail: data.items.isEmpty ? nil : "\(data.items.count) 人"
                    )
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("屏蔽用户")
        .task { await load() }
        .refreshable { await load(force: true) }
        .alert(
            pendingUnblock.map { "解除对「\($0.name)」的屏蔽？" } ?? "解除屏蔽？",
            isPresented: Binding(
                get: { pendingUnblock != nil },
                set: { if !$0 { pendingUnblock = nil } }
            )
        ) {
            if let member = pendingUnblock {
                Button("解除屏蔽") {
                    pendingUnblock = nil
                    Task { await remove(member.id) }
                }
            }
            Button("取消", role: .cancel) {
                pendingUnblock = nil
            }
        } message: {
            Text("解除后，该用户的主题和回复会重新正常显示。")
        }
    }

    private var inputFieldRow: some View {
        HStack(spacing: AccountSettingsMetrics.rowSpacing) {
            SeekIconTile(symbol: "person.badge.minus")
            TextField("输入要屏蔽的用户名", text: $name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    guard canAdd else { return }
                    Task { await add() }
                }
                .disabled(loader.isUpdating)
                .accessibilityIdentifier("blocked-members-input")
        }
    }

    private func addButton(fullWidth: Bool) -> some View {
        SettingsActionPill(
            title: "添加",
            busyTitle: "添加中…",
            isBusy: isAdding,
            primary: true,
            fullWidth: fullWidth
        ) {
            Task { await add() }
        }
        .disabled(!canAdd)
        .accessibilityIdentifier("blocked-members-add-button")
    }

    private func load(force: Bool = false) async {
        await loader.load(account.website, .blocks, userID: userID, force: force)
    }

    private func add() async {
        guard let value = normalizedInput, !isDuplicateInput, !loader.isUpdating else { return }
        isAdding = true
        defer { isAdding = false }
        if await loader.action(account.website, .block(name: value), userID: userID) != nil {
            name = ""
            await load(force: true)
        }
    }

    private func remove(_ id: Int) async {
        guard !loader.isUpdating else { return }
        removingID = id
        defer { removingID = nil }
        if await loader.action(account.website, .unblock(memberID: id), userID: userID) != nil {
            await load(force: true)
        }
    }
}

private struct BlockedMemberRow: View {
    let member: BlockedMember
    let isRemoving: Bool
    let isDisabled: Bool
    let onUnblock: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                        AvatarView(name: member.name, url: member.avatarURL, size: AccountSettingsMetrics.iconSize)
                        identityText
                    }
                    unblockButton
                }
            } else {
                HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                    AvatarView(name: member.name, url: member.avatarURL, size: AccountSettingsMetrics.iconSize)
                    identityText
                    Spacer(minLength: 8)
                    unblockButton
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blocked-member-\(member.id)")
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: AccountSettingsMetrics.rowLineSpacing) {
            Text(member.name)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.seekInk)
            Text("UID \(String(member.id))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var unblockButton: some View {
        Button(action: onUnblock) {
            ZStack {
                Text("解除")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.seekInk)
                    .opacity(isRemoving ? 0 : 1)
                if isRemoving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minWidth: 56, minHeight: 34)
            .background(Color.seekTray, in: .capsule)
        }
        .buttonStyle(.seekRow)
        .disabled(isDisabled)
        .accessibilityIdentifier("unblock-member-\(member.id)")
        .accessibilityLabel("解除对 \(member.name) 的屏蔽")
    }
}
