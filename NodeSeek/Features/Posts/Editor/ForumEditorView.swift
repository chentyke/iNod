import NodeSeekCore
import NodeSeekClient
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
    @State private var showsImage = false
    @State private var showsImageLibrary = false
    @State private var showsVote = false
    @State private var showsReceive = false
    @State private var imageURL = ""
    @FocusState private var isFocused: Bool

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
                        Menu("插入图片", systemImage: "photo") {
                            Button("上传或选择已有图片", systemImage: "photo.on.rectangle") { isFocused = false; showsImageLibrary = true }
                            Button("插入图片链接", systemImage: "link") { isFocused = false; showsImage = true }
                        }
                        Spacer()
                        Text("\(draft.content.count) 字").font(.caption).foregroundStyle(.secondary)
                    }.labelStyle(.iconOnly).frame(minHeight: 44).padding(.horizontal, 20).padding(.vertical, 6)
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(.red).padding(.horizontal, 20).padding(.vertical, 8) }
                Text("草稿自动保存在本机").font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            .seekCanvas()
            .disabled(sending)
            .navigationTitle(request.mode.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍后再写") { dismiss() }.disabled(sending) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "提交中…" : (request.mode.rawValue.hasPrefix("edit") ? "保存" : "发布")) { submitOrConfirm() }
                        .disabled(sending || draft.validation(for: request.mode) != nil || ownerID != account.user?.id)
                }
            }
            .interactiveDismissDisabled(sending)
            .task(id:account.user?.id) { initialize() }
            .task { await categories.refresh() }
            .task(id:draft) {
                guard initialized,!published,let ownerID else { return }
                do { try await Task.sleep(for:.milliseconds(300)); EditorDraftStore.save(draft,ownerID:ownerID,mode:request.mode) } catch { }
            }
            .onDisappear { if initialized,!published,let ownerID { EditorDraftStore.save(draft,ownerID:ownerID,mode:request.mode) } }
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
            .sheet(isPresented: $showsImageLibrary) {
                if let ownerID {
                    NavigationStack {
                        NodeImageLibraryView(userID: ownerID) { url in
                            selection = nil
                            insert(prefix: "\n![图片](", suffix: ")\n", placeholder: url.absoluteString)
                        }
                    }
                }
            }
            .alert("插入图片", isPresented: $showsImage) {
                TextField("https://图片地址", text: $imageURL).textInputAutocapitalization(.never)
                Button("插入") { insertImage() }
                Button("取消", role: .cancel) { imageURL = "" }
            } message: { Text("填写可以在网页中显示的图片链接。") }
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
    private func insertImage() {
        guard let url = URL(string: imageURL), ["http", "https"].contains(url.scheme ?? ""), url.host() != nil else { error = "请输入有效的图片链接。"; return }
        selection = nil
        insert(prefix: "\n![图片](", suffix: ")\n", placeholder: url.absoluteString)
        imageURL = ""
    }
    private func submitOrConfirm() {
        guard draft.validation(for: request.mode) == nil else { return }
        if request.mode.cost(for: draft) > 0 { confirmsCost = true }
        else { Task { await publish() } }
    }
    private func publish() async {
        guard !sending, let ownerID, account.user?.id == ownerID else { return }
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
        } catch { self.error = error.localizedDescription }
    }
}
