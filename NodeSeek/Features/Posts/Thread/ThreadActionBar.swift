import NodeSeekClient
import NodeSeekCore
import SwiftUI

struct ThreadActionBar: View {
    let post: PostSummary
    let threadTitle: String
    let canReply: Bool
    let showsReply: Bool
    let isCollected: Bool
    let isUpdatingCollection: Bool
    @Binding var request: ThreadReplyRequest?
    @Binding var isWriting: Bool
    let onCollection: () -> Void
    let onSignIn: () -> Void
    let onPublished: () -> Void

    @Environment(AccountSession.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var editorTransition
    @State private var showsPhotos = false
    @State private var uploading = false
    @FocusState private var focused: Bool
    @State private var draft = ThreadReplyDraft()
    @State private var ownerID: Int?
    @State private var sending = false
    @State private var justSent = false
    @State private var editor: EditorRequest?
    @State private var failure: String?

    private let cornerRadius: CGFloat = 23
    private var replyOutline: Color {
        guard colorScheme == .light else { return .seekHairline.opacity(0.55) }
        return .black.opacity(isWriting ? 0.18 : 0.05)
    }

    private var replyShadow: Color {
        guard colorScheme == .light else { return .black.opacity(0.10) }
        return .black.opacity(isWriting ? 0.12 : 0.025)
    }

    private var mode: EditorMode { .reply(postID: post.id) }
    private var canSend: Bool {
        canReply && !sending && !uploading && ownerID != nil && ownerID == account.user?.id
            && (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.images.isEmpty)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if showsReply {
                replySurface
                    .matchedTransitionSource(id: "reply", in: editorTransition) { $0.clipShape(.rect(cornerRadius: cornerRadius)) }
                    .shadow(color: replyShadow, radius: 4, y: 2)
            } else {
                Spacer(minLength: 0)
            }

            // Move the glass and its symbols together, including when a quick tap reverses the animation.
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 8) { readingActions }
            }
            .padding(.leading, 8)
            .fixedSize()
            .scaleEffect(isWriting ? 0.01 : 1, anchor: .trailing)
            .opacity(isWriting ? 0 : 1)
            .frame(width: isWriting ? 0 : nil, alignment: .trailing)
            .allowsHitTesting(!isWriting)
            .accessibilityHidden(isWriting)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: isWriting)
        .onChange(of: isWriting) { _, writing in focused = writing && editor == nil }
        .onChange(of: focused) { _, hasFocus in
            if !hasFocus, editor == nil, !showsPhotos, failure == nil { isWriting = false }
        }
        .modifier(EditorPhotoSelection(ownerID: ownerID, presented: $showsPhotos, uploading: $uploading) { url in
            draft.images.append(url)
            save()
        } onError: { failure = $0 })
        .onChange(of: showsPhotos) { _, presented in
            if !presented, isWriting, editor == nil { focused = true }
        }
        .onChange(of: account.user?.id, initial: true) { _, _ in
            isWriting = false
            justSent = false
            restore()
        }
        .task(id: justSent) {
            guard justSent else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                justSent = false
            } catch {}
        }
        .onChange(of: showsReply) { if !showsReply { isWriting = false } }
        .task(id: request) {
            guard let request else { return }
            defer { if !Task.isCancelled { self.request = nil } }
            do {
                try await account.withConfirmedSignIn(onSignedOut: onSignIn) { user in
                    guard canReply, !sending else { return }
                    justSent = false
                    if !isWriting || ownerID != user.id { restore() }
                    if case .respond(let target) = request {
                        draft.target = target
                        save()
                    }
                    isWriting = true
                    focused = true
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { failure = SiteError.displayMessage(for: error) }
            }
        }
        .sheet(item: $editor, onDismiss: { focused = isWriting }) { request in
            let page = ForumEditorView(request: request, legacyDraftKey: "reply-draft-\(post.id)", replyTitle: threadTitle, onDraftSaved: { value, author in
                guard author == account.user?.id else { return }
                draft = ThreadReplyDraft(stored: value, postID: post.id)
            }) { _ in
                draft = ThreadReplyDraft()
                isWriting = false
                justSent = true
                onPublished()
            }
            Group {
                if reduceMotion { page }
                else { page.navigationTransition(.zoom(sourceID: "reply", in: editorTransition)) }
            }
            .presentationSizing(.page)
        }
        .alert("回复未完成", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }

    @ViewBuilder private var readingActions: some View {
        Button(action: onCollection) {
            Image(isCollected ? .inkSavedPost : .inkSavePost)
                .foregroundStyle(Color.seekButtonIcon)
                .frame(width: 46, height: 46)
                .contentShape(.circle)
        }
        .accessibilityLabel(isCollected ? "取消收藏" : "收藏")
        .disabled(isUpdatingCollection)
        .glassEffect(.regular.interactive(), in: .circle)
        ShareLink(item: post.url) {
            Image(.inkSharePost)
                .foregroundStyle(Color.seekButtonIcon)
                .frame(width: 46, height: 46)
                .contentShape(.circle)
        }
        .accessibilityLabel("分享帖子")
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var replyPrompt: String {
        if isWriting { return "写回复…" }
        if account.signInStatus == .signedOut { return "登录后回复" }
        if justSent { return "回复已发送" }
        if uploading { return "正在上传图片…" }
        if !draft.images.isEmpty { return "\(draft.images.count) 张图片" }
        if let target = draft.target {
            return target.quote == nil ? "回复 \(target.name)…" : "引用 \(target.name)…"
        }
        return "写回复…"
    }

    private var replySurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isWriting, let target = draft.target, target.quote != nil {
                ReplyQuoteHeader(target: target) {
                    draft.target = nil
                    save()
                }
                .accessibilityHidden(editor != nil)
                .padding(.leading, 16).padding(.trailing, 5).padding(.top, 6)
                .disabled(sending)
            } else if isWriting, let target = draft.target {
                HStack(spacing: 6) {
                    Image(.inkReply)
                    Text("回复 \(target.name)  #\(target.floor)").lineLimit(1)
                    Button {
                        draft.target = nil
                        save()
                    } label: {
                        Image(.inkDiscardReply).foregroundStyle(Color.seekButtonIcon).frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("取消回复此楼")
                }
                .font(.subheadline).foregroundStyle(Color.seekGreen)
                .padding(.horizontal, 16).padding(.top, 4)
                .disabled(sending)
            }
            // Keep the text and its glass on screen while the field moves with the keyboard.
            ZStack(alignment: .leading) {
                TextField("", text: Binding(get: { draft.text }, set: { text in
                    guard isWriting, editor == nil, !sending else { return }
                    draft.text = text
                    save()
                }), axis: .vertical)
                .foregroundStyle(.primary)
                .lineLimit(1...(isWriting ? 4 : 1))
                .focused($focused)
                .accessibilityLabel("回复正文")
                .allowsHitTesting(isWriting && !sending)
                .accessibilityHidden(!isWriting)

                if draft.text.isEmpty {
                    Text(verbatim: replyPrompt)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .font(.body)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: isWriting ? nil : 46, alignment: .leading)
            .overlay {
                if !isWriting {
                    Button { request = .write } label: {
                        Color.clear.contentShape(.rect)
                    }
                    .accessibilityLabel(account.signInStatus == .signedOut ? "登录后回复" : "写回复")
                    .accessibilityValue(draft.text)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!canReply || request != nil || sending)
                }
            }
            .padding(.top, isWriting ? (draft.target == nil ? 14 : 4) : 0)
            .padding(.bottom, isWriting ? 6 : 0)

            if isWriting {
                if !draft.images.isEmpty {
                    ReplyPhotoStrip(images: draft.images) { index in
                        draft.images.remove(at: index)
                        save()
                    }
                    .disabled(sending)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                }
                writingActions
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(replyOutline, lineWidth: 0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background {
            if isWriting, editor == nil, !showsPhotos, failure == nil {
                ReplyOutsideTap(cornerRadius: cornerRadius) { isWriting = false }
            }
        }
    }

    private var writingActions: some View {
        HStack(spacing: 4) {
            Button { showsPhotos = true } label: {
                Group {
                    if uploading { ProgressView().controlSize(.small) }
                    else { Image(.inkAttachPhoto).foregroundStyle(Color.seekButtonIcon) }
                }
                .frame(width: 44, height: 44).contentShape(.rect)
            }
            .accessibilityLabel(uploading ? "正在上传图片" : "选择图片")
            .disabled(uploading)
            Spacer(minLength: 0)
            Button { openEditor() } label: {
                Image(.inkExpandEditor)
                    .foregroundStyle(Color.seekButtonIcon)
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .accessibilityLabel("完整编辑")
            .disabled(uploading)
            Button { Task { await send() } } label: {
                Group {
                    if sending { ProgressView().controlSize(.small).tint(Color.seekButtonIcon) }
                    else {
                        Image(.inkSendReply)
                            .font(.body.weight(.bold))
                            .foregroundStyle(canSend ? Color.seekButtonIconOnFill : .seekButtonIcon)
                    }
                }
                .frame(width: 36, height: 36)
                .background(canSend ? Color.seekGreen : Color(uiColor: .quaternarySystemFill), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
            }
            .buttonStyle(.seekRow)
            .accessibilityLabel(sending ? "正在发送" : "发送回复")
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 8).padding(.trailing, 5).padding(.bottom, 4)
        .disabled(sending)
    }

    private func restore() {
        ownerID = account.user?.id
        let stored = ownerID.flatMap { EditorDraftStore.load(ownerID: $0, mode: mode) }
        draft = ThreadReplyDraft(stored: stored, postID: post.id)
    }

    private func save() {
        guard let ownerID, ownerID == account.user?.id else { return }
        let value = draft.editorDraft(postID: post.id)
        EditorDraftStore.save(value.content.isEmpty ? nil : value, ownerID: ownerID, mode: mode)
    }

    private func openEditor() {
        isWriting = true
        editor = EditorRequest(mode: mode, seed: EditorDraft())
    }

    private func send() async {
        guard isWriting, canSend, let ownerID else { return }
        let value = draft.editorDraft(postID: post.id)
        let revision = account.revision
        sending = true
        defer { sending = false }
        do {
            let result: ReactionResponse = try await account.website.perform(.publish(draft: value, mode: mode), userID: ownerID)
            guard result.success else { throw SiteError.message(result.message ?? "回复未能发送，请重试。") }
            if EditorDraftStore.load(ownerID: ownerID, mode: mode) == value {
                EditorDraftStore.save(nil, ownerID: ownerID, mode: mode)
            }
            guard account.revision == revision else { return }
            isWriting = false
            restore()
            justSent = true
            onPublished()
            await account.refresh(force: true)
        } catch {
            guard account.revision == revision else { return }
            failure = SiteError.displayMessage(for: error)
        }
    }
}
