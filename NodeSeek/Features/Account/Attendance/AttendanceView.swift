import NodeSeekCore
import NodeSeekClient
import SwiftUI

enum AttendanceSignInMode: Equatable {
    case fixed
    case random
}

enum AttendanceMetrics {
    static let cardPadding: CGFloat = 20
    /// Trims font line-height air above the first text line so visual top and bottom gaps match.
    static let topGlyphTrim: CGFloat = 3
    static let bottomGlyphTrim: CGFloat = 3
    static let blockSpacing: CGFloat = 16
    static let textSpacing: CGFloat = 6
    static let buttonSpacing: CGFloat = 10
    static let pillSpacing: CGFloat = 8
    static let pillHorizontalPadding: CGFloat = 12
    static let pillVerticalPadding: CGFloat = 6

    static let rowVerticalInset: CGFloat = 9
    static let rowHorizontalInset: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let rankWidth: CGFloat = 30
    static let podiumBadgeSize: CGFloat = 24
    static let avatarSize: CGFloat = 36
    static let separatorInset: CGFloat = rankWidth + rowSpacing + avatarSize + rowSpacing
    static let memberRowInsets = EdgeInsets(
        top: rowVerticalInset,
        leading: rowHorizontalInset,
        bottom: rowVerticalInset,
        trailing: rowHorizontalInset
    )

    static func statusCardInsets(hasBottomCapsule: Bool) -> EdgeInsets {
        EdgeInsets(
            top: cardPadding - topGlyphTrim,
            leading: cardPadding,
            bottom: hasBottomCapsule ? cardPadding : cardPadding - bottomGlyphTrim,
            trailing: cardPadding
        )
    }
}

struct AttendanceView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loader = ResourceLoader<AttendanceBoard>()
    @State private var page = 1
    @State private var signingMode: AttendanceSignInMode?

    var body: some View {
        AccountDataView(loader: loader, retry: { await load(force: true) }) { data in
            let hasBottomCapsule = data.gain == nil || data.order != nil || account.user?.coins != nil
            List {
                Section {
                    AttendanceStatusCard(
                        board: data,
                        coins: account.user?.coins,
                        signingMode: signingMode
                    ) { mode in
                        Task { await signIn(mode: mode) }
                    }
                    .listRowInsets(AttendanceMetrics.statusCardInsets(hasBottomCapsule: hasBottomCapsule))
                    .listRowBackground(Color.seekCard)
                    .listRowSeparator(.hidden)
                }

                Section {
                    if data.items.isEmpty {
                        Text("今天还没有人签到")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.seekCard)
                    }
                    ForEach(data.items) { member in
                        NavigationLink(value: MemberDestination.profile(member.id)) {
                            AttendanceMemberRow(member: member, isCurrentUser: member.id == userID)
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + AttendanceMetrics.separatorInset }
                        .listRowInsets(AttendanceMetrics.memberRowInsets)
                        .listRowBackground(Color.seekCard)
                    }
                    if data.hasNext && loader.error == nil && !loader.isLoadingFirstPage {
                        LoadMoreRow(error: loader.nextPageError, isEnabled: signingMode == nil && !loader.updating) {
                            await load(nextPage: true)
                        }
                        .id(page)
                        .listRowBackground(Color.seekCard)
                    }
                } header: {
                    SeekSectionTitle(
                        title: "今日签到榜",
                        detail: data.total > 0 ? "\(data.total.formatted()) 人" : nil
                    )
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.28), value: data.gain != nil)
        }
        .navigationTitle("每日签到")
        .task { if loader.value == nil { await load() } }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false, nextPage: Bool = false) async {
        guard !nextPage || loader.value?.hasNext == true else { return }
        let requestedPage = nextPage ? page + 1 : 1
        let force = force || (nextPage && loader.nextPageError != nil)
        let merge = nextPage ? appendPage(\AttendanceBoard.items) : nil
        if await loader.load(account.website, .attendance(requestedPage), userID: userID, force: force, appending: merge) != nil {
            page = requestedPage
        }
    }

    private func signIn(mode: AttendanceSignInMode) async {
        guard loader.value?.gain == nil, signingMode == nil, !loader.updating else { return }
        signingMode = mode
        defer { signingMode = nil }
        if let response = await loader.action(account.website, .attend(random: mode == .random), userID: userID) {
            account.updateCoins(response.current)
            await load(force: true)
            await account.refresh(force: true)
        }
    }
}
