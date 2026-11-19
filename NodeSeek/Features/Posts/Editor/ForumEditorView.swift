import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct ForumEditorView: View {
    let request: EditorRequest
    var legacyDraftKey: String? = nil
    var replyTitle: String? = nil
    var onDraftSaved: ((EditorDraft, Int) -> Void)? = nil
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
    @State private var showsPhotos = false
    @State private var insertingPhotos = false
    @State private var replyContext = ThreadReplyDraft()
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsVote = false
    @State private var showsReceive = false
    @FocusState private var isFocused: Bool
    private var storedDraft: EditorDraft {
        guard case .reply(let postID) = request.mode else { return draft }
        var reply = replyContext
        reply.text = draft.content
        return reply.editorDraft(postID: postID)
    }
    private var canPublish: Bool {
        !sending && !insertingPhotos && ownerID != nil && ownerID == account.user?.id
            && storedDraft.validation(for: request.mode) == nil
            && (replyTitle == nil || !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !replyContext.images.isEmpty)
    }

    var body: some View {
        ForumNavigationStack {
            Group {
                if let replyTitle {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        GeometryReader { proxy in
                            replyWorkspace(title: replyTitle, availableSize: proxy.size)
                        }
                    } else {
                        replyWorkspace(title: replyTitle)
                    }
                } else { standardWorkspace }
            }
            .disabled(sending)
            .navigationTitle(request.mode.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { saveForLater(); dismiss() } label: {
                        if replyTitle != nil { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                        else { Text("稍后再写") }
                    }
                    .accessibilityLabel("稍后再写")
                    .disabled(sending || insertingPhotos)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submitOrConfirm) {
                        if replyTitle != nil {
                            if sending { ProgressView() }
                            else { Image(systemName: "arrow.up").fontWeight(.semibold) }
                        } else {
                            Text(sending ? "提交中…" : (request.mode.rawValue.hasPrefix("edit") ? "保存" : "发布"))
                        }
                    }
                    .accessibilityLabel(replyTitle != nil ? "发送回复" : (request.mode.rawValue.hasPrefix("edit") ? "保存" : "发布"))
                    .disabled(!canPublish)
                }
            }
            .interactiveDismissDisabled(sending || insertingPhotos)
            .task(id:account.user?.id) { initialize() }
            .task { if request.mode == .newPost { await categories.refresh() } }
            .modifier(EditorPhotoSelection(ownerID: ownerID, presented: $showsPhotos, uploading: $insertingPhotos) { url in
                if replyTitle != nil { replyContext.images.append(url) }
                else { draft.appendHostedImage(url) }
            } onError: { error = $0 })
            .task(id: storedDraft) {
                guard initialized, let ownerID else { return }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    if !published { EditorDraftStore.save(storedDraft, ownerID: ownerID, mode: request.mode) }
                } catch {}
            }
            .onDisappear(perform: saveForLater)
            .onChange(of:account.revision) { if initialized,ownerID != account.user?.id { dismiss() } }
            .onChange(of: preview) { if replyTitle == nil, preview { isFocused = false } }
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

    private func replyHeading(title: String, showsQuote: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let target = replyContext.target, target.quote == nil {
                Label("回复 \(target.name)  #\(target.floor)", systemImage: "arrowshape.turn.up.left")
                    .font(.subheadline).foregroundStyle(Color.seekGreen)
            }
            Text(verbatim: title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsQuote { replyQuote(lines: 1) }
        }
    }

    @ViewBuilder private func replyQuote(lines: Int) -> some View {
        if let target = replyContext.target, target.quote != nil {
            ReplyQuoteHeader(target: target, excerptLines: lines) { replyContext.target = nil }
                .accessibilityIdentifier("full-reply-quote")
        }
    }

    private var replyPhotos: some View {
        ReplyPhotoStrip(images: replyContext.images) { replyContext.images.remove(at: $0) }
            .disabled(sending)
    }

    private var replyPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let target = replyContext.target, target.quote != nil, case .reply(let postID) = request.mode {
                    ForumMarkdown(markdown: target.reference(postID: postID) + draft.content)
                } else {
                    ForumMarkdown(markdown: draft.content)
                }
                ForEach(replyContext.images.indices, id: \.self) { index in
                    ForumImageView(url: replyContext.images[index], alt: "图片 \(index + 1)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
        }
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("reply-preview")
    }

    private var replyTextEditor: some View {
        TextEditor(text: $draft.content, selection: $selection)
            .font(.body)
            .focused($isFocused)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("正文，支持 Markdown")
            .overlay(alignment: .topLeading) {
                if draft.content.isEmpty {
                    Text("写回复…").foregroundStyle(.secondary)
                        .padding(.leading, 5).padding(.top, 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, -5).padding(.top, 8)
    }

    private func replyWorkspace(title: String, availableSize: CGSize = .zero) -> some View {
        let wide = availableSize.width >= 720 && !typeSize.isAccessibilitySize
        let compactHeight = availableSize != .zero && availableSize.height < 500
        let hasPhotos = !replyContext.images.isEmpty
        let hasSideColumn = wide && (preview || hasPhotos || replyContext.target?.quote != nil)
        let headerPhotos = !wide && compactHeight && !preview && hasPhotos
        let previewAction = preview ? (wide ? "收起预览" : "继续撰写") : "预览"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                replyHeading(title: title, showsQuote: !wide && !preview)
                if headerPhotos {
                    replyPhotos.frame(width: replyContext.images.count == 1 ? 60 : 148, height: 60)
                }
            }
            .padding(.top, compactHeight ? 8 : 18).padding(.bottom, compactHeight ? 8 : 16)

            Rectangle().fill(.separator).frame(height: 0.5)
            HStack(alignment: .top, spacing: 0) {
                if wide || !preview {
                    replyTextEditor
                } else {
                    replyPreview
                }
                if hasSideColumn {
                    Rectangle().fill(.separator).frame(width: 0.5).padding(.horizontal, 16)
                    Group {
                        if preview {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("预览").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.top, 12)
                                replyPreview
                            }
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    replyQuote(lines: 5)
                                    if hasPhotos { replyPhotos }
                                }
                                .padding(.vertical, 12)
                            }
                        }
                    }
                    .frame(width: min(availableSize.width * (preview ? 0.42 : 0.32), preview ? 440 : 320))
                }
            }
            if !wide, !headerPhotos, !preview, hasPhotos {
                replyPhotos.padding(.vertical, 8)
            }
            if let error {
                Text(error).font(.subheadline).foregroundStyle(.red).padding(.vertical, 6)
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 12) {
                    if wide || !preview {
                        HStack(spacing: 2) {
                            formatMenu.frame(width: 44, height: 44)
                            photoButton.frame(width: 44, height: 44)
                            Button("表情", systemImage: "face.smiling") { isFocused = false; showsStickers = true }
                                .frame(width: 44, height: 44)
                        }
                        .padding(.horizontal, 6)
                        .glassEffect(.regular, in: .capsule)
                    }
                    Spacer(minLength: 0)
                    Button {
                        preview.toggle()
                        isFocused = wide || !preview
                    } label: {
                        Label(previewAction, systemImage: preview ? (wide ? "eye.slash" : "pencil") : "eye")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(previewAction)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.seekInk)
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: wide ? .infinity : SeekLayout.columnWidth)
        .frame(maxWidth: .infinity)
        .background(Color.seekCard.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: preview)
    }

    private var standardWorkspace: some View {
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
                    formatMenu
                    Button("表情", systemImage: "face.smiling") { isFocused = false; showsStickers = true }
                    photoButton
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
        .seekCanvas(margins: .keepsGutter)
    }

    private var formatMenu: some View {
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
    }

    private var photoButton: some View {
        Button {
            error = nil
            showsPhotos = true
        } label: {
            if insertingPhotos { ProgressView().accessibilityLabel("正在上传图片") }
            else { Label("选择图片", systemImage: "photo") }
        }
        .disabled(insertingPhotos || ownerID == nil || ownerID != account.user?.id)
    }

    private func saveForLater() {
        guard initialized, !published, let ownerID else { return }
        let value = storedDraft
        EditorDraftStore.save(value, ownerID: ownerID, mode: request.mode)
        onDraftSaved?(value, ownerID)
    }

    private func initialize() {
        guard !initialized, let user = account.user else { return }
        ownerID = user.id
        draft = EditorDraftStore.load(ownerID: user.id, mode: request.mode) ?? request.seed
        if !request.seed.content.isEmpty, draft.content != request.seed.content,
           case .reply = request.mode { draft.content += "\n\n" + request.seed.content }
        if case .reply(let postID) = request.mode {
            replyContext = ThreadReplyDraft(stored: draft, postID: postID)
            draft.content = replyContext.text
        }
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
    private func submitOrConfirm() {
        guard canPublish else { return }
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
            let result: ReactionResponse = try await account.website.perform(.publish(draft: storedDraft, mode: request.mode), userID: ownerID)
            guard result.success else { throw SiteError.message(result.message ?? "提交未成功，请重试。") }
            published = true
            EditorDraftStore.save(nil, ownerID: ownerID, mode: request.mode)
            if importedLegacy,let legacyDraftKey { UserDefaults.standard.removeObject(forKey:legacyDraftKey) }
            onPublished(result)
            dismiss()
            await account.refresh(force: true)
        } catch { self.error = SiteError.displayMessage(for: error) }
    }
}
