import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct ConversationView: View {
    let peer: MessageRecipient
    let userID: Int
    @Environment(AccountSession.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadID: UUID?
    @State private var isSending = false
    @State private var error: LoadFailure?
    private var conversation: ConversationData? { account.inbox.conversations[peer.id] }
    @State private var draft = MessageDraft()
    @State private var draftLoaded = false
    @State private var hasLoadedOnce = false
    @State private var isVisible = false
    @State private var isNearBottom = true
    @State private var hasNewMessages = false
    @State private var scrollAfterSend = false
    @State private var showsPreview = false
    @State private var showsStickers = false
    @FocusState private var isFocused: Bool

    private var messageText: String { draft.content.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let peerName = conversation?.peer.name ?? peer.name

        AccountDataView(value: conversation, error: error, isBusy: loadID != nil || isSending,
                        margins: .keepsGutter, in: .scrollView,
                        retry: { await refreshManually() }) { data in
            ScrollViewReader { proxy in
                ScrollView {
                    ConversationTimeline(messages: data.items, userID: userID)
                }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(isNearBottom ? .bottom : .top, for: .sizeChanges)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .overlay {
                    if data.items.isEmpty {
                        ContentUnavailableView("暂无消息", image: .inkEmptyConversation)
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
                        Button("新消息", image: .inkNewMessage) {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            hasNewMessages = false
                        }.buttonStyle(.glass).padding(.bottom, 8)
                    }
                }
            }
        }
        .navigationTitle(peerName)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            MessageComposer(text: $draft.content, isBusy: isSending,
                canSend: !isSending && !messageText.isEmpty && conversation != nil && account.user?.id == userID,
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
        .task {
            let shouldForce = hasLoadedOnce
            hasLoadedOnce = true
            await load(force: shouldForce, replacingCurrentLoad: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard !Task.isCancelled, scenePhase.isPollingActive else { continue }
                if !isSending { await load(force: true) }
            }
        }
        .onChange(of: scenePhase) { previous, phase in
            if previous != .active, phase == .active, isVisible, hasLoadedOnce, !isSending {
                Task { await load(force: true) }
            }
        }
        .onChange(of: account.inbox.unreadCount) { previous, count in
            if count > previous, isVisible, !isSending {
                Task { await load(force: true) }
            }
        }
        .refreshable { await refreshManually() }
        .sheet(isPresented: $showsPreview) {
            ForumNavigationStack {
                ScrollView { ForumMarkdown(markdown: messageText).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                    .navigationTitle("私信预览").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("完成") { showsPreview = false } }

            }
        }
        .sheet(isPresented: $showsStickers) { StickerPickerView { sticker in draft.content += ":\(sticker.code):" } }
    }

    private func refreshManually() async {
        guard !isSending else { return }
        await load(force: true, replacingCurrentLoad: true)
    }

    private func load(force: Bool = false, replacingCurrentLoad: Bool = false) async {
        guard account.user?.id == userID, !Task.isCancelled, replacingCurrentLoad || loadID == nil else { return }
        let id = UUID()
        loadID = id
        defer { if loadID == id { loadID = nil } }
        error = nil
        let revision = account.revision
        do {
            try await account.inbox.loadConversation(peerID: peer.id, userID: userID, force: force)
        } catch is CancellationError {
            return
        } catch {
            if loadID == id, account.revision == revision, !Task.isCancelled { self.error = LoadFailure(error) }
            return
        }
        guard loadID == id else { return }
        loadID = nil
        guard !Task.isCancelled, isVisible, scenePhase == .active, account.revision == revision else { return }
        do {
            try await account.inbox.markConversationRead(peerID: peer.id, userID: userID)
        } catch is CancellationError {
        } catch {
            if loadID == nil, account.revision == revision, !Task.isCancelled { self.error = LoadFailure(error) }
        }
    }

    private func send() async {
        let text = messageText
        guard !text.isEmpty, !isSending, conversation != nil, account.user?.id == userID, peer.id != userID else { return }
        isSending = true
        error = nil
        let revision = account.revision
        do {
            defer { isSending = false }
            try await account.inbox.send(text, markdown: true, peerID: peer.id, userID: userID)
            guard account.revision == revision else { return }
            draft.content = ""
            MessageDraftStore.save(draft, ownerID: userID, peerID: peer.id)
            scrollAfterSend = true
        } catch is CancellationError {
            return
        } catch {
            if account.revision == revision { self.error = LoadFailure(error) }
            return
        }
        await load(force: true, replacingCurrentLoad: true)
    }
}
