import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct ConversationView: View {
    let peer: MessageRecipient
    let userID: Int
    @Environment(AccountSession.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoading = false
    @State private var isSending = false
    @State private var error: LoadFailure?
    private var conversation: ConversationData? { account.inbox.conversations[peer.id] }
    @State private var draft = MessageDraft()
    @State private var draftLoaded = false
    @State private var isVisible = false
    @State private var isNearBottom = true
    @State private var hasNewMessages = false
    @State private var scrollAfterSend = false
    @State private var showsPreview = false
    @State private var showsStickers = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let peerName = conversation?.peer.name ?? peer.name

        AccountDataView(value: conversation, error: error, isBusy: isLoading || isSending, retry: { await load(force: true) }) { data in
            ScrollViewReader { proxy in
                ScrollView {
                    ConversationTimeline(messages: data.items, userID: userID)
                }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(isNearBottom ? .bottom : .top, for: .sizeChanges)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .overlay {
                    if data.items.isEmpty {
                        ContentUnavailableView("暂无消息", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.bottom
                        - geometry.contentOffset.y - geometry.containerSize.height <= 80
                } action: { _, near in
                    isNearBottom = near
                    if near { hasNewMessages = false }
                }
                .onChange(of: data.items.last?.id, initial: true) { oldID, newID in
                    guard newID != nil else { return }
                    if oldID == nil || isNearBottom || scrollAfterSend {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        hasNewMessages = false; scrollAfterSend = false
                    } else { hasNewMessages = true }
                }
                .overlay(alignment: .bottom) {
                    if hasNewMessages {
                        Button("新消息", systemImage: "arrow.down") {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            hasNewMessages = false
                        }.buttonStyle(.glass).padding(.bottom, 8)
                    }
                }
            }
        }
        .seekCanvas(margins: .keepsGutter)
        .navigationTitle(peerName)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            MessageComposer(draft: $draft, isBusy: isSending,
                canSend: !isSending && !isLoading && !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && conversation != nil && account.user?.id == userID,
                focus: $isFocused,
                onStickers: { isFocused = false; showsStickers = true },
                onPreview: { isFocused = false; showsPreview = true },
                onSend: { Task { await send() } })
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: MemberDestination.profile(peer.id)) {
                    AvatarView(name: peerName, url: peer.avatarURL, size: 38)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("查看 \(peerName) 的主页")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .onAppear {
            if !draftLoaded { draft = MessageDraftStore.load(ownerID: userID, peerID: peer.id); draftLoaded = true }
            isVisible = true
        }
        .onDisappear { isVisible = false }
        .onChange(of: draft) { if draftLoaded { MessageDraftStore.save(draft, ownerID: userID, peerID: peer.id) } }
        .task(id: isVisible && scenePhase == .active) {
            guard isVisible, scenePhase == .active else { return }
            await load(force: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard !Task.isCancelled, isVisible, scenePhase == .active else { return }
                if !isSending && !isLoading { await load(force: true) }
            }
        }
        .refreshable { await load(force: true) }
        .sheet(isPresented: $showsPreview) {
            ForumNavigationStack {
                ScrollView { ForumMarkdown(markdown: draft.content).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                    .navigationTitle("私信预览").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("完成") { showsPreview = false } }

            }
        }
        .sheet(isPresented:$showsStickers) { StickerPickerView { sticker in draft.isMarkdown = true; draft.content += ":\(sticker.code):" } }
    }

    private func load(force: Bool = false) async {
        guard account.user?.id == userID, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        let revision = account.revision
        do {
            try await account.inbox.loadConversation(peerID: peer.id, userID: userID, force: force)
            guard !Task.isCancelled, isVisible, scenePhase == .active, account.revision == revision else { return }
            try await account.inbox.markConversationRead(peerID: peer.id, userID: userID)
        } catch is CancellationError {
        } catch {
            if account.revision == revision, !Task.isCancelled { self.error = LoadFailure(error) }
        }
    }

    private func send() async {
        let text = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, !isLoading, conversation != nil, account.user?.id == userID, peer.id != userID else { return }
        isSending = true
        defer { isSending = false }
        error = nil
        let revision = account.revision
        do {
            try await account.inbox.send(text, markdown: draft.isMarkdown, peerID: peer.id, userID: userID)
            guard account.revision == revision else { return }
            draft.content = ""
            MessageDraftStore.save(draft, ownerID: userID, peerID: peer.id)
            scrollAfterSend = true
            await load(force: true)
        } catch is CancellationError {
        } catch {
            if account.revision == revision { self.error = LoadFailure(error) }
        }
    }
}
