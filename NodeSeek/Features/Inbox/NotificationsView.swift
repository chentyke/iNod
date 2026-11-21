import NodeSeekClient
import NodeSeekCore
import SwiftUI

struct NotificationsView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator
    @State private var selection = NotificationTab.activity
    @State private var isMarkingRead = false
    @State private var confirmsRead = false
    @State private var readError: String?

    var body: some View {
        Group {
            if let user = account.user {
                // Give the list's refresh control room below the fixed header.
                VStack(spacing: 0) {
                    header(userID: user.id)
                    InboxPages(userID: user.id, hasUnreadNotices: hasUnread(.activity), selection: $selection)
                }
                .id(user.id)
            } else {
                MemberSignInView()
            }
        }
        .background(Color.seekCanvas.ignoresSafeArea())
        .navigationTitle("通知")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .alert("无法标为已读", isPresented: Binding(
            get: { readError != nil },
            set: { if !$0 { readError = nil } }
        )) {
            Button("好", role: .cancel) { readError = nil }
        } message: {
            Text(readError ?? "")
        }
    }

    private func header(userID: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("通知")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.seekInk)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if hasUnread(selection) {
                    markAllReadButton(userID: userID)
                }
            }
            .frame(minHeight: 44)

            HStack(spacing: 24) {
                ForEach(NotificationTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .animation(reduceMotion ? nil : NotificationTab.animation(reduceMotion: false), value: selection)
        }
        .padding(.top, 8)
        .padding(.horizontal, SeekLayout.gutter)
        .frame(maxWidth: SeekLayout.columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Color.seekHairline.frame(height: 0.5)
        }
    }

    private func tabButton(_ tab: NotificationTab) -> some View {
        let isSelected = tab == selection
        let isUnread = hasUnread(tab)
        return Button {
            withAnimation(NotificationTab.animation(reduceMotion: reduceMotion)) { selection = tab }
        } label: {
            Text(tab.rawValue)
                .font(.headline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.seekInk : .secondary)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
                .overlay(alignment: .topTrailing) {
                    if isUnread {
                        Circle()
                            .fill(Color.seekGreen)
                            .frame(width: 5, height: 5)
                            .offset(x: 3, y: 8)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Capsule()
                            .fill(Color.seekInk)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "inbox-tab", in: indicator)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isUnread ? Text("有未读") : Text(""))
    }

    private func markAllReadButton(userID: Int) -> some View {
        Button {
            if selection == .messages { confirmsRead = true }
            else { Task { await markAllRead(.activity, userID: userID) } }
        } label: {
            Image(selection == .messages ? .inkMarkMailRead : .inkReadAll)
                .font(.headline)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.seekButtonIcon)
        .accessibilityLabel("全部标为已读")
        .disabled(isMarkingRead)
        .confirmationDialog("将所有私聊标为已读？", isPresented: $confirmsRead, titleVisibility: .visible) {
            Button("全部标为已读") { Task { await markAllRead(.messages, userID: userID) } }
        }
    }

    private func hasUnread(_ tab: NotificationTab) -> Bool {
        switch tab {
        case .activity:
            account.inbox.notices.values.contains { $0.items.contains { !$0.viewed } }
        case .messages:
            account.inbox.threads?.items.contains { !$0.viewed } == true
        }
    }

    private func markAllRead(_ tab: NotificationTab, userID: Int) async {
        guard !isMarkingRead else { return }
        isMarkingRead = true
        defer { isMarkingRead = false }
        do {
            switch tab {
            case .messages: try await account.inbox.markAllMessagesRead(userID: userID)
            case .activity: try await account.inbox.markAllNoticesRead(userID: userID)
            }
        } catch is CancellationError { }
        catch { readError = SiteError.displayMessage(for: error) }
    }
}
