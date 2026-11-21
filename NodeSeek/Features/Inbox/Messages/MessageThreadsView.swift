import NodeSeekClient
import NodeSeekCore
import SwiftUI

struct MessageThreadsView: View {
    let userID: Int
    let isSelected: Bool
    @Environment(AccountSession.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var isVisible = false
    @State private var error: LoadFailure?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var memberSearch: (query: String, recipients: [MessageRecipient], error: LoadFailure?)?

    var body: some View {
        let search = searchTerm
        let memberResults = memberSearch.flatMap { $0.query == search ? $0 : nil }
        let matches = matches(for: search, recipients: memberResults?.recipients ?? [])

        InboxList(items: matches,
                  emptyTitle: emptyTitle(for: search),
                  emptySymbol: search.isEmpty ? .inkEmptyInbox : .inkNoMatchingMail,
                  error: memberResults?.error ?? error,
                  isBusy: isLoading || (!search.isEmpty && memberResults == nil),
                  reload: { await refresh(search) },
                  isSelected: isSelected, leadingContent: searchSection) { match in
            NavigationLink(value: MemberDestination.conversation(match.recipient)) {
                switch match {
                case .thread(let thread):
                    InboxRow(name: thread.name, avatarURL: thread.recipient.avatarURL,
                             title: thread.name, detail: preview(for: thread),
                             date: ForumDate.parse(thread.createdAt), isUnread: !thread.viewed)
                case .member(let member):
                    InboxRow(name: member.name, avatarURL: member.avatarURL,
                             title: member.name, detail: "开始私聊",
                             date: nil, isUnread: false)
                }
            }
            .navigationLinkIndicatorVisibility(.hidden)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: isSelected) { _, selected in
            if !selected { searchFocused = false }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task {
            await load()
            hasLoadedOnce = !Task.isCancelled
        }
        .task(id: isSelected) {
            guard isSelected else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard !Task.isCancelled, scenePhase.isPollingActive else { continue }
                await load(force: true)
            }
        }
        .onChange(of: scenePhase) { previous, phase in
            if previous != .active, phase == .active, isSelected, isVisible, hasLoadedOnce {
                Task { await load(force: true) }
            }
        }
        .task(id: search) {
            memberSearch = nil
            guard !search.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            await findMembers(search)
        }
    }

    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var searchSection: some View {
        Section {
            searchField
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listSectionSpacing(4)
    }

    private var searchField: some View {
        let searchTitle = "搜索私聊或找人"
        return HStack(spacing: 8) {
            Image(.inkSearchMail)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("", text: $query)
                .accessibilityLabel(searchTitle)
                .overlay(alignment: .leading) {
                    if query.isEmpty {
                        Text(searchTitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .frame(minHeight: 44)
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(.inkClearInput)
                        .foregroundStyle(Color.seekButtonIcon)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .font(.subheadline)
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 0)
        .background(Color.seekTray, in: .capsule)
    }

    private func matches(for search: String, recipients: [MessageRecipient]) -> [ConversationMatch]? {
        let threads = account.inbox.threads?.items
        guard !search.isEmpty else { return threads?.map(ConversationMatch.thread) }

        let id = MemberAddress.parse(search)
        let memberIDs = Set(recipients.map(\.id))
        let existing = (threads ?? []).filter {
            $0.id == id || memberIDs.contains($0.id) ||
                $0.name.localizedStandardContains(search) || $0.preview.localizedStandardContains(search)
        }
        var shown = Set(existing.map(\.id))
        let newMembers = recipients.filter { $0.id != userID && shown.insert($0.id).inserted }
        return existing.map(ConversationMatch.thread) + newMembers.map(ConversationMatch.member)
    }

    private func emptyTitle(for search: String) -> String {
        if search.isEmpty { return "暂无私聊" }
        if MemberAddress.parse(search) == userID { return "不能给自己发私信" }
        return "没有找到会话或用户"
    }

    private func refresh(_ search: String) async {
        async let threads: Void = load(force: true)
        if !search.isEmpty { await findMembers(search, force: true) }
        await threads
    }

    private func findMembers(_ search: String, force: Bool = false) async {
        do {
            let recipients: [MessageRecipient]
            if let id = MemberAddress.parse(search) {
                if id == userID { recipients = [] }
                else {
                    let profile: AccountProfile = try await account.website.publicResource(.profile(id), force: force)
                    recipients = profile.id == id ? [profile.recipient] : []
                }
            } else if search.contains("://") {
                recipients = []
            } else {
                let response: MemberSearchResponse = try await account.website.load(.memberSearch(search), force: force)
                recipients = response.memberList.map { MessageRecipient(id: $0.id, name: $0.member_name) }
            }
            guard !Task.isCancelled, searchTerm == search else { return }
            memberSearch = (search, recipients, nil)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, searchTerm == search else { return }
            memberSearch = (search, [], LoadFailure(error))
        }
    }

    private func preview(for thread: MessageThread) -> String {
        let markdown = thread.isMarkdown == true
            ? try? AttributedString(markdown: thread.preview, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            : nil
        let text = markdown.map { String($0.characters) } ?? thread.preview
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do { try await account.inbox.loadThreads(userID: userID, force: force) }
        catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = LoadFailure(error) } }
    }

}
