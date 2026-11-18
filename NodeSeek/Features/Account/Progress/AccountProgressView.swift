import NodeSeekCore
import NodeSeekClient
import SwiftUI

enum ProgressMetrics {
    static let cardPadding: CGFloat = 20
    /// Trims font line-height air above the first text line so visual top and bottom gaps match.
    static let topGlyphTrim: CGFloat = 2
    static let bottomGlyphTrim: CGFloat = 3
    static let blockSpacing: CGFloat = 16
    static let textSpacing: CGFloat = 6
    static let progressSpacing: CGFloat = 8
    static let pillSpacing: CGFloat = 8
    static let pillHorizontalPadding: CGFloat = 12
    static let pillVerticalPadding: CGFloat = 6

    static let rowHorizontalInset: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let iconTileSize: CGFloat = 36
    static let iconRowSeparatorInset: CGFloat = iconTileSize + rowSpacing
    static let progressRowVerticalInset: CGFloat = 14
    static let navigationRowVerticalInset: CGFloat = 6

    static let tierBadgeSize: CGFloat = 24
    static let tierRowVerticalInset: CGFloat = 10
    static let tierSeparatorInset: CGFloat = tierBadgeSize + rowSpacing

    static let progressRowInsets = EdgeInsets(
        top: progressRowVerticalInset,
        leading: rowHorizontalInset,
        bottom: progressRowVerticalInset,
        trailing: rowHorizontalInset
    )

    static let navigationRowInsets = EdgeInsets(
        top: navigationRowVerticalInset,
        leading: rowHorizontalInset,
        bottom: navigationRowVerticalInset,
        trailing: rowHorizontalInset
    )

    static let tierRowInsets = EdgeInsets(
        top: tierRowVerticalInset,
        leading: rowHorizontalInset,
        bottom: tierRowVerticalInset,
        trailing: rowHorizontalInset
    )

    static func levelCardInsets(hasBottomCapsule: Bool) -> EdgeInsets {
        EdgeInsets(
            top: cardPadding - topGlyphTrim,
            leading: cardPadding,
            bottom: hasBottomCapsule ? cardPadding : cardPadding - bottomGlyphTrim,
            trailing: cardPadding
        )
    }
}

struct AccountProgressView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var loader = ResourceLoader<DailyProgress>()

    private var levelProgress: AccountLevel.Progress? {
        AccountLevel.progress(forCoins: account.user?.coins)
    }

    var body: some View {
        ResourceContent(loader: loader, retry: { await refreshAll() }) { data in
            let progress = levelProgress
            List {
                Section {
                    AccountLevelCard(progress: progress)
                        .listRowInsets(ProgressMetrics.levelCardInsets(hasBottomCapsule: progress != nil))
                        .listRowBackground(Color.seekCard)
                        .listRowSeparator(.hidden)
                }

                Section {
                    DailyProgressRow(kind: .postBonus, quota: data.postBonus)
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + ProgressMetrics.iconRowSeparatorInset }
                        .listRowInsets(ProgressMetrics.progressRowInsets)
                        .listRowBackground(Color.seekCard)
                    DailyProgressRow(kind: .commentBonus, quota: data.commentBonus)
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + ProgressMetrics.iconRowSeparatorInset }
                        .listRowInsets(ProgressMetrics.progressRowInsets)
                        .listRowBackground(Color.seekCard)
                    DailyProgressRow(kind: .freeLike, quota: data.freeLike)
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + ProgressMetrics.iconRowSeparatorInset }
                        .listRowInsets(ProgressMetrics.progressRowInsets)
                        .listRowBackground(Color.seekCard)
                } header: {
                    SeekSectionTitle(title: "今日进度")
                }

                Section {
                    AccountNavigationRow(title: "每日签到", symbol: "calendar.badge.checkmark", destination: .attendance)
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + ProgressMetrics.iconRowSeparatorInset }
                        .listRowInsets(ProgressMetrics.navigationRowInsets)
                        .listRowBackground(Color.seekCard)
                    AccountNavigationRow(title: "鸡腿明细", symbol: "list.bullet.rectangle", destination: .ledger(.chicken))
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + ProgressMetrics.iconRowSeparatorInset }
                        .listRowInsets(ProgressMetrics.navigationRowInsets)
                        .listRowBackground(Color.seekCard)
                }

                Section {
                    ForEach(AccountLevel.tiers) { tier in
                        LevelTierRow(tier: tier, currentLevel: progress?.level)
                            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + ProgressMetrics.tierSeparatorInset }
                            .listRowInsets(ProgressMetrics.tierRowInsets)
                            .listRowBackground(Color.seekCard)
                    }
                } header: {
                    SeekSectionTitle(title: "等级门槛", detail: "100 × 等级²")
                } footer: {
                    Text("等级按当前鸡腿数实时计算，用于解锁对应阅读权限的帖子。")
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
        }
        .navigationTitle("等级与进度")
        .task {
            await load()
            if account.user?.coins == nil {
                await account.refresh()
            }
        }
        .refreshable {
            await refreshAll()
        }
    }

    private func load(force: Bool = false) async {
        await loader.load(account.website, .dailyProgress, force: force)
    }

    private func refreshAll() async {
        async let progress: Void = load(force: true)
        async let session: Void = account.refresh(force: true)
        _ = await (progress, session)
    }
}
