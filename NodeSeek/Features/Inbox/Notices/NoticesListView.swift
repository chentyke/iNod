import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct NoticesListView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openAccountPost) private var openPost
    @Environment(\.openMemberDestination) private var openMember
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var isVisible = false
    @State private var isUpdating = false
    @State private var loadErrors: [NoticeKind: LoadFailure] = [:]
    @State private var updateError: LoadFailure?

    var body: some View {
        let items = activity
        InboxList(items: items, emptyTitle: "暂无互动通知", emptySymbol: "bell",
                  error: updateError ?? loadErrors[.replies] ?? loadErrors[.mentions],
                  isBusy: isLoading || isUpdating, reload: { await load(force: true) },
                  leadingContent: EmptyView()) { item in
            let notice = item.notice
            let action = item.kind == .replies ? "回复了你" : "提到了你"

            Button {
                openPost(notice.post)
                if !notice.viewed { Task { await mark(notice.id, kind: item.kind) } }
            } label: {
                InboxRow(name: notice.author,
                         avatarURL: MessageRecipient(id: notice.authorID, name: notice.author).avatarURL,
                         title: notice.title, detail: "\(notice.author)\(action)",
                         date: item.date, isUnread: !notice.viewed)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("查看作者主页", systemImage: "person.crop.circle") { openMember(.profile(notice.authorID)) }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !notice.viewed {
                    Button("标为已读", systemImage: "checkmark") {
                        Task { await mark(notice.id, kind: item.kind) }
                    }
                    .tint(.seekGreen)
                    .disabled(isUpdating)
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task {
            await load()
            hasLoadedOnce = true
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard !Task.isCancelled, scenePhase.isPollingActive else { continue }
                await load(force: true)
            }
        }
        .onChange(of: scenePhase) { previous, phase in
            if previous != .active, phase == .active, isVisible, hasLoadedOnce {
                Task { await load(force: true) }
            }
        }
    }

    private var activity: [InboxNotice]? {
        let pages = account.inbox.notices
        guard !pages.isEmpty else { return nil }
        let items = NoticeKind.allCases.flatMap { kind in
            (pages[kind]?.items ?? []).map { InboxNotice(notice: $0, kind: kind) }
        }
        return items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        updateError = nil
        loadErrors.removeAll()
        async let replies: Void = load(.replies, force: force)
        async let mentions: Void = load(.mentions, force: force)
        _ = await (replies, mentions)
    }

    private func load(_ kind: NoticeKind, force: Bool) async {
        do { try await account.inbox.loadNotices(kind, userID: userID, force: force) }
        catch is CancellationError { }
        catch { if !Task.isCancelled { loadErrors[kind] = LoadFailure(error) } }
    }

    private func mark(_ id: Int, kind: NoticeKind) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        updateError = nil
        do { try await account.inbox.markNoticesRead(kind, ids: [id], userID: userID) }
        catch is CancellationError { }
        catch { updateError = LoadFailure(error) }
    }
}
