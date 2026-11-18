import NodeSeekCore
import NodeSeekClient
import SwiftUI

private enum ProfileEditorTab: Hashable, CaseIterable {
    case edit
    case preview

    var title: String {
        switch self {
        case .edit: "编辑"
        case .preview: "预览"
        }
    }
}

struct ProfileEditorView: View {
    let userID: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSession.self) private var account
    @State private var loader = AccountLoader<AccountProfile>()
    @State private var mode: ProfileEditorTab = .edit
    @State private var bio = ""
    @State private var signature = ""
    @State private var readme = ""
    @State private var baselineBio = ""
    @State private var baselineSignature = ""
    @State private var baselineReadme = ""
    @State private var initialized = false

    private var changed: Bool {
        initialized && (bio != baselineBio || signature != baselineSignature || readme != baselineReadme)
    }

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { _ in
            List {
                Section {
                    SeekSegmentedPicker(
                        title: "资料视图",
                        selection: $mode,
                        options: ProfileEditorTab.allCases,
                        label: \.title
                    )
                    .accessibilityIdentifier("profile-editor-mode-picker")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if mode == .edit {
                    editSections
                } else {
                    previewSections
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .disabled(loader.isUpdating)
        }
        .navigationTitle("编辑资料")
        .interactiveDismissDisabled(loader.isUpdating)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(loader.isUpdating ? "保存中…" : "保存") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(loader.value == nil || loader.isUpdating || !changed)
                .accessibilityIdentifier("profile-editor-save-button")
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var editSections: some View {
        Section {
            TextField("用一句话介绍自己", text: $bio, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityIdentifier("profile-editor-bio")
                .listRowBackground(Color.seekCard)
        } header: {
            SeekSectionTitle(
                title: "一句话介绍",
                detail: bio.isEmpty ? nil : "\(bio.count) 字"
            )
        } footer: {
            Text("显示在个人主页头像下方。")
        }

        Section {
            TextField("在每条回复下方显示的签名", text: $signature, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("profile-editor-signature")
                .listRowBackground(Color.seekCard)
        } header: {
            SeekSectionTitle(title: "个人签名", detail: "支持 Markdown")
        } footer: {
            Text("支持基础 Markdown 格式，不支持图片和引用。")
        }

        Section {
            TextField("写在个人主页上的介绍", text: $readme, axis: .vertical)
                .lineLimit(8...18)
                .accessibilityIdentifier("profile-editor-readme")
                .listRowBackground(Color.seekCard)
        } header: {
            SeekSectionTitle(title: "主页介绍", detail: "支持 Markdown")
        } footer: {
            Text("支持标题、列表、代码块与链接，保存后在个人主页展示。")
        }
    }

    @ViewBuilder
    private var previewSections: some View {
        Section {
            if bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("尚未填写一句话介绍")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.seekCard)
            } else {
                Text(bio)
                    .foregroundStyle(Color.seekInk)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.seekCard)
            }
        } header: {
            SeekSectionTitle(title: "一句话介绍")
        }

        Section {
            if signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("尚未填写个人签名")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.seekCard)
            } else {
                ForumMarkdown(markdown: signature)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.seekCard)
            }
        } header: {
            SeekSectionTitle(title: "个人签名")
        }

        Section {
            if readme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("尚未填写主页介绍")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.seekCard)
            } else {
                ForumMarkdown(markdown: readme)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.seekCard)
            }
        } header: {
            SeekSectionTitle(title: "主页介绍")
        }
    }

    private func load(force: Bool = false) async {
        if !initialized,
           let cached: AccountProfile = account.website.cached(
               key: account.website.key(for: .editableProfile(userID), viewerID: userID)
           ) {
            apply(cached)
        }
        let hadEditsBeforeLoad = changed
        await loader.load(account.website, .editableProfile(userID), userID: userID, force: force)
        if let profile = loader.value, (!initialized || !hadEditsBeforeLoad || force) {
            apply(profile)
        }
    }

    private func apply(_ profile: AccountProfile) {
        let nextBio = profile.bio ?? ""
        let nextSignature = profile.signature ?? ""
        let nextReadme = profile.readme ?? ""
        bio = nextBio
        signature = nextSignature
        readme = nextReadme
        baselineBio = nextBio
        baselineSignature = nextSignature
        baselineReadme = nextReadme
        initialized = true
    }

    private func save() async {
        guard changed else { return }
        if await loader.action(
            account.website,
            .updateProfile(bio: bio, signature: signature, readme: readme),
            userID: userID
        ) != nil {
            baselineBio = bio
            baselineSignature = signature
            baselineReadme = readme
            await account.refresh()
            dismiss()
        }
    }
}
