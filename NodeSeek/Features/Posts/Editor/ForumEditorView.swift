import NodeSeekCore
import NodeSeekClient
import PhotosUI
import SwiftUI

struct ForumEditorView: View {
    let request: EditorRequest
    var legacyDraftKey: String? = nil
    let onPublished: (ReactionResponse) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSession.self) private var account
    @State private var draft = EditorDraft()
    private var categories: CategoryStore { account.categories }
    @State private var selection: TextSelection?
    @State private var preview = false
    @State private var sending = false
    @State private var initialized = false
    @State private var published = false
    @State private var showsLegacyImport = false
    @State private var importedLegacy = false
    @State private var ownerID: Int?
    @State private var error: String?
    @State private var confirmsCost = false
    @State private var showsStickers = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var photoUploadTask: Task<Void, Never>?
    @State private var showsVote = false
    @State private var showsReceive = false
    @FocusState private var isFocused: Bool
    private var insertingPhotos: Bool { photoUploadTask != nil || !pickedPhotos.isEmpty }

    var body: some View {
        ForumNavigationStack {
            VStack(spacing: 0) {
                if request.mode.editsTitle {
                    TextField("帖子标题", text: $draft.title, axis: .vertical)
                        .font(.title3.bold()).lineLimit(1...3).padding(18)
                        .background(Color.seekCard, in: .rect(cornerRadius: 20)).padding(.horizontal, 16).padding(.top, 12)
                }
                if request.mode.editsTitle {
                    HStack(spacing: 12) {
                        if request.mode == .newPost {
                            Picker("版块", selection: $draft.category) {
                                ForEach(categories.items.filter { !$0.id.isEmpty && !$0.adminOnly }) { Text($0.title).tag($0.id) }
                            }.labelsHidden()
                        }
                        Picker("阅读限制", selection: $draft.rank) {
                            Text("公开").tag(0)
                            ForEach(Array(0...max(0, min(6, account.user?.forumRank ?? 0))).dropFirst(), id: \.self) { Text("Lv \($0)").tag($0) }
                            Text("仅自己可见").tag(255)
                        }.labelsHidden()
                        Spacer()
                    }.font(.subheadline).padding(.horizontal, 12).padding(.vertical, 6)
                }
                SeekSegmentedPicker(title: "编辑器模式", selection: $preview, options: [false, true], label: { $0 ? "预览" : "撰写" })
                    .padding(.horizontal, 20).padding(.vertical, 12)
                if preview {
                    ScrollView { ForumMarkdown(markdown: draft.content).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    TextEditor(text: $draft.content, selection: $selection)
                        .font(.body).focused($isFocused).scrollContentBackground(.hidden)
                        .padding(12).background(Color.seekCard, in: .rect(cornerRadius: 24)).padding(.horizontal, 16)
                        .accessibilityLabel("正文，支持 Markdown")
                        .overlay(alignment: .topLeading) {
                            if draft.content.isEmpty { Text("写下你想分享的内容…").foregroundStyle(.secondary).padding(.top, 20).padding(.leading, 36).allowsHitTesting(false) }
                        }
                    HStack(spacing: 20) {
                        Menu("文字格式", systemImage: "textformat") {
                            Button("加粗") { insert(prefix: "**", suffix: "**", placeholder: "加粗文字") }
                            Button("斜体") { insert(prefix: "*", suffix: "*", placeholder: "斜体文字") }
                            Button("标题") { insert(prefix: "\n## ", suffix: "\n", placeholder: "标题") }
                            Button("引用") { insert(prefix: "\n> ", suffix: "\n", placeholder: "引用内容") }
                            Button("代码") { insert(prefix: "\n```\n", suffix: "\n```\n", placeholder: "代码") }
                            Button("链接") { insert(prefix: "[", suffix: "](https://)", placeholder: "链接文字") }
                            Button("列表") { insert(prefix: "\n- ", suffix: "\n", placeholder: "列表项") }
                            Button("表格") { insert(prefix: "\n| 项目 | 内容 |\n| --- | --- |\n| ", suffix: " |  |\n", placeholder: "项目") }
                            Button("创建投票", systemImage: "chart.bar.xaxis") { isFocused = false; showsVote = true }
                            Button("星尘收款",systemImage:"sparkles") { isFocused = false; showsReceive = true }
                            if let legacyDraftKey,UserDefaults.standard.string(forKey:legacyDraftKey)?.isEmpty == false {
                                Button("导入旧版草稿") { showsLegacyImport = true }
                            }
                        }
                        Button("表情", systemImage: "face.smiling") { isFocused = false; showsStickers = true }
                        PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .images) {
                            Label("选择图片", systemImage: "photo")
                        }
                        .disabled(insertingPhotos || ownerID == nil || ownerID != account.user?.id)
                        Spacer()
                        if insertingPhotos {
                            ProgressView("正在上传图片").controlSize(.small).font(.caption)
                        } else {
                            Text("\(draft.content.count) 字").font(.caption).foregroundStyle(.secondary)
                        }
                    }.labelStyle(.iconOnly).frame(minHeight: 44).padding(.horizontal, 20).padding(.vertical, 6)
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(.red).padding(.horizontal, 20).padding(.vertical, 8) }
                Text("草稿自动保存在本机").font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            .seekCanvas()
            .disabled(sending)
            .navigationTitle(request.mode.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍后再写") { dismiss() }.disabled(sending || insertingPhotos) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "提交中…" : (request.mode.rawValue.hasPrefix("edit") ? "保存" : "发布")) { submitOrConfirm() }
                        .disabled(sending || insertingPhotos || draft.validation(for: request.mode) != nil || ownerID != account.user?.id)
                }
            }
            .interactiveDismissDisabled(sending || insertingPhotos)
            .task(id:account.user?.id) { initialize() }
            .task { await categories.refresh() }
            .onChange(of: pickedPhotos) { _, photos in
                guard !photos.isEmpty, photoUploadTask == nil else { return }
                pickedPhotos = []
                photoUploadTask = Task {
                    await attachPhotos(photos)
                    photoUploadTask = nil
                }
            }
            .task(id:draft) {
                guard initialized,!published,let ownerID else { return }
                do { try await Task.sleep(for:.milliseconds(300)); EditorDraftStore.save(draft,ownerID:ownerID,mode:request.mode) } catch { }
            }
            .onDisappear {
                photoUploadTask?.cancel()
                if initialized,!published,let ownerID { EditorDraftStore.save(draft,ownerID:ownerID,mode:request.mode) }
            }
            .onChange(of:account.revision) { if initialized,ownerID != account.user?.id { dismiss() } }
            .onChange(of: preview) { if preview { isFocused = false } }
            .confirmationDialog("确认发布？", isPresented: $confirmsCost, titleVisibility: .visible) {
                Button("消耗 \(request.mode.cost(for: draft)) 个鸡腿并发布") { Task { await publish() } }
                Button("取消", role: .cancel) { }
            } message: { Text("这次操作按官网规则收费，提交后不能退回。") }
            .sheet(isPresented: $showsStickers) {
                StickerPickerView { sticker in insert(prefix: "", suffix: "", placeholder: ":\(sticker.code):") }
            }
            .sheet(isPresented:$showsReceive) { StardustRequestCreator { link in selection = nil; insert(prefix:"\n",suffix:"\n",placeholder:link) } }
            .sheet(isPresented: $showsVote) { VoteCreatorView { id in selection = nil; insert(prefix: "\n", suffix: "\n", placeholder: "nsapp://vote?id=\(id)") } }
            .alert("导入旧版草稿？",isPresented:$showsLegacyImport) {
                Button("导入") {
                    if let legacyDraftKey,let text = UserDefaults.standard.string(forKey:legacyDraftKey) {
                        draft.content += (draft.content.isEmpty ? "" : "\n\n") + text; importedLegacy = true
                    }
                }
                Button("取消",role:.cancel) { }
            } message: { Text("旧版草稿没有账号标记，请确认它属于你。导入后会保存到当前账号的草稿。") }

        }
    }

    private func initialize() {
        guard !initialized, let user = account.user else { return }
        ownerID = user.id
        draft = EditorDraftStore.load(ownerID: user.id, mode: request.mode) ?? request.seed
        if !request.seed.content.isEmpty, draft.content != request.seed.content,
           case .reply = request.mode { draft.content += "\n\n" + request.seed.content }
        initialized = true
        isFocused = true
    }
    private func insert(prefix: String, suffix: String, placeholder: String) {
        let range: Range<String.Index>
        if let selection, case .selection(let selected) = selection.indices { range = selected }
        else { range = draft.content.endIndex..<draft.content.endIndex }
        let chosen = range.isEmpty ? placeholder : String(draft.content[range])
        let position = draft.content.distance(from: draft.content.startIndex, to: range.lowerBound)
        draft.content.replaceSubrange(range, with: prefix + chosen + suffix)
        selection = TextSelection(insertionPoint: draft.content.index(draft.content.startIndex, offsetBy: position + prefix.count + chosen.count + suffix.count))
    }
    private func attachPhotos(_ photos: [PhotosPickerItem]) async {
        guard let user = account.user, user.id == ownerID else { return }
        let revision = account.revision
        let preferences = NodeImageUploadPreferences(userID: user.id)
        let options = preferences.imageOptions(username: user.name)
        let expiration = preferences.deleteAfterDays
        var links: [URL] = []
        error = nil
        defer {
            if !Task.isCancelled, preferences.copyAfterUpload, !links.isEmpty, account.revision == revision {
                UIPasteboard.general.string = links.map { preferences.linkFormat.text(for: $0) }.joined(separator: "\n")
            }
        }

        do {
            let key = try NodeImageKeyStore.read(userID: user.id)
            guard NodeImageAPI.validKey(key) else {
                throw SiteError.message("请到「我的」中的「图片上传与管理」连接 NodeImage 后再选图。")
            }
            let history = account.nodeImageHistory
            for photo in photos {
                let prepared = try await NodeImageInput.photo(photo).prepare()
                let payload = try await Task.detached(priority: .userInitiated) {
                    try UploadImageProcessor.render(prepared, options: options)
                }.value
                guard !Task.isCancelled, account.revision == revision else { return }
                let image = try await history.client.upload(
                    image: payload.data, format: payload.format, key: key, deleteAfterDays: expiration
                )
                guard !Task.isCancelled, account.revision == revision else { return }
                history.recordUpload(image, userID: user.id, key: key)
                draft.appendHostedImage(image.url)
                links.append(image.url)
            }
        } catch {
            if !Task.isCancelled, account.revision == revision { self.error = SiteError.displayMessage(for: error) }
        }
    }
    private func submitOrConfirm() {
        guard !insertingPhotos, draft.validation(for: request.mode) == nil else { return }
        if request.mode.cost(for: draft) > 0 { confirmsCost = true }
        else { Task { await publish() } }
    }
    private func publish() async {
        guard !sending, !insertingPhotos, let ownerID, account.user?.id == ownerID else { return }
        sending = true; error = nil
        defer { sending = false }
        do {
            if request.mode == .newPost, !categories.items.contains(where: { $0.id == draft.category && !$0.adminOnly }) {
                throw SiteError.message("这个版块已不能发帖，请重新选择版块。")
            }
            let result: ReactionResponse = try await account.website.perform(.publish(draft: draft, mode: request.mode), userID: ownerID)
            published = true
            EditorDraftStore.save(nil, ownerID: ownerID, mode: request.mode)
            if importedLegacy,let legacyDraftKey { UserDefaults.standard.removeObject(forKey:legacyDraftKey) }
            onPublished(result)
            dismiss()
            await account.refresh(force: true)
        } catch { self.error = SiteError.displayMessage(for: error) }
    }
}
