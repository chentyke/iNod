import NodeSeekClient
import NodeSeekCore
import SwiftUI

struct NotificationsView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    switch selection {
                    case .activity: NoticesListView(userID: user.id)
                    case .messages: MessageThreadsView(userID: user.id)
                    }
                }
            } else {
                MemberSignInView()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
        HStack(spacing: 8) {
            if typeSize.isAccessibilitySize {
                tabPicker.pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                tabPicker.pickerStyle(.segmented)
            }
            if hasUnread {
                Button("全部标为已读", systemImage: "checkmark.circle") {
                    if selection == .messages { confirmsRead = true }
                    else { Task { await markAllRead(.activity, userID: userID) } }
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .disabled(isMarkingRead)
                .confirmationDialog("将所有私聊标为已读？", isPresented: $confirmsRead, titleVisibility: .visible) {
                    Button("全部标为已读") { Task { await markAllRead(.messages, userID: userID) } }
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .readableColumn()
        .padding(.bottom, 4)
    }

    private var tabPicker: some View {
        Picker("通知类型", selection: $selection) {
            ForEach(NotificationTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
    }

    private var hasUnread: Bool {
        switch selection {
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
