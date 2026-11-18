import NodeSeekCore
import NodeSeekClient
import SwiftUI

enum StardustMetrics {
    static let cardPadding: CGFloat = 20
    /// Trims font line-height air above the eyebrow label and below the rounded balance digits so visual top and bottom margins match.
    static let topGlyphTrim: CGFloat = 3
    static let bottomGlyphTrim: CGFloat = 7.5
    static let cardSpacing: CGFloat = 16
    static let balanceLabelSpacing: CGFloat = 6

    static let rowVerticalInset: CGFloat = 11
    static let rowHorizontalInset: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let rowLineSpacing: CGFloat = 4
    static let iconSize: CGFloat = 36
    static let separatorInset: CGFloat = iconSize + rowSpacing

    static let chipSpacing: CGFloat = 8
    static let chipHorizontalPadding: CGFloat = 10
    static let chipVerticalPadding: CGFloat = 5

    static func balanceCardInsets(stacked: Bool) -> EdgeInsets {
        EdgeInsets(
            top: cardPadding - topGlyphTrim,
            leading: cardPadding,
            bottom: stacked ? cardPadding : cardPadding - bottomGlyphTrim,
            trailing: cardPadding
        )
    }

    static let recordRowInsets = EdgeInsets(
        top: rowVerticalInset,
        leading: rowHorizontalInset,
        bottom: rowVerticalInset,
        trailing: rowHorizontalInset
    )

    static let filterBarInsets = EdgeInsets(
        top: 10,
        leading: rowHorizontalInset,
        bottom: 10,
        trailing: rowHorizontalInset
    )
}

struct StardustHistoryView: View {
    let memberID: Int
    @Environment(AccountSession.self) private var account
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loader = ResourceLoader<StardustRecords>()
    @State private var draftFilter: StardustFilter
    @State private var appliedFilter: StardustFilter
    @State private var page = 1
    @State private var lastCursor: Int?
    @State private var showsFilter = false
    @State private var showsTransfer = false
    @State private var filterRevision = 0
    @State private var loadedFilterRevision: Int?
    @State private var balanceAtLastLoad: Int?

    init(memberID: Int, initialReference: String = "") {
        self.memberID = memberID
        let initial = StardustFilter(reference: initialReference).normalized() ?? StardustFilter()
        _draftFilter = State(initialValue: initial)
        _appliedFilter = State(initialValue: initial)
    }

    private var isOwnHistory: Bool {
        memberID == account.user?.id
    }

    var body: some View {
        ResourceContent(loader: loader, retry: { await load(force: true) }) { data in
            let activeChips = appliedFilter.chips
            List {
                if isOwnHistory {
                    Section {
                        StardustBalanceCard(stardust: account.user?.stardust) {
                            showsTransfer = true
                        }
                        .listRowInsets(StardustMetrics.balanceCardInsets(stacked: typeSize.isAccessibilitySize))
                        .listRowBackground(Color.seekCard)
                        .listRowSeparator(.hidden)
                    }
                }

                Section {
                    if !activeChips.isEmpty {
                        StardustActiveFilterBar(
                            chips: activeChips,
                            onRemove: { removeChip($0) },
                            onClearAll: { updateAppliedFilter(StardustFilter()) }
                        )
                        .listRowInsets(StardustMetrics.filterBarInsets)
                        .listRowBackground(Color.seekCard)
                    }

                    if data.records.isEmpty {
                        Text(activeChips.isEmpty ? "暂无星尘收支记录" : "没有符合筛选条件的记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.seekCard)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(data.records) { record in
                        StardustRecordRow(
                            record: record,
                            onFilterPeer: { peerID in
                                var next = appliedFilter
                                next.peer = String(peerID)
                                updateAppliedFilter(next)
                            },
                            onFilterReference: { refID in
                                var next = appliedFilter
                                next.reference = String(refID)
                                updateAppliedFilter(next)
                            }
                        )
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + StardustMetrics.separatorInset }
                        .listRowInsets(StardustMetrics.recordRowInsets)
                        .listRowBackground(Color.seekCard)
                    }

                    if hasNextPage(data) && loader.error == nil && !loader.isLoadingFirstPage && loadedFilterRevision == filterRevision {
                        LoadMoreRow(
                            error: loader.nextPageError,
                            isEnabled: !showsFilter && !loader.loading && !loader.updating
                        ) {
                            await load(nextPage: true)
                        }
                        .id(page)
                        .listRowBackground(Color.seekCard)
                    }
                } header: {
                    SeekSectionTitle(
                        title: "收支记录",
                        detail: activeChips.isEmpty ? nil : "已筛选"
                    )
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.24), value: activeChips)
        }
        .navigationTitle("星尘明细")
        .navigationDestination(isPresented: $showsTransfer) {
            StardustTransferView(userID: memberID)
        }
        .task(id: filterRevision) {
            guard loadedFilterRevision != filterRevision else { return }
            await load()
        }
        .onChange(of: showsTransfer) { _, isShowing in
            guard !isShowing, isOwnHistory, loadedFilterRevision != nil,
                  account.user?.stardust != balanceAtLastLoad else { return }
            Task { await load(force: true) }
        }
        .onChange(of: account.user?.stardust) { _, latest in
            guard !showsTransfer, isOwnHistory, loadedFilterRevision != nil,
                  latest != balanceAtLastLoad else { return }
            Task { await load(force: true) }
        }
        .refreshable {
            await load(force: true)
            if isOwnHistory {
                await account.refresh(force: true)
                balanceAtLastLoad = account.user?.stardust
            }
        }
        .toolbar {
            Button {
                draftFilter = appliedFilter
                showsFilter = true
            } label: {
                Label(
                    appliedFilter.chips.isEmpty ? "筛选" : "筛选（已启用）",
                    systemImage: appliedFilter.chips.isEmpty
                        ? "line.3.horizontal.decrease"
                        : "line.3.horizontal.decrease.circle.fill"
                )
            }
            .accessibilityIdentifier("stardust-filter-button")
        }
        .sheet(isPresented: $showsFilter) {
            StardustFilterSheet(
                draft: $draftFilter,
                hasAppliedFilter: !appliedFilter.isEmpty,
                onApply: applyFilters,
                onClear: clearFiltersFromSheet
            )
        }
    }

    private func applyFilters() {
        guard let normalized = draftFilter.normalized() else { return }
        showsFilter = false
        updateAppliedFilter(normalized)
    }

    private func clearFiltersFromSheet() {
        draftFilter = StardustFilter()
        if !appliedFilter.isEmpty {
            showsFilter = false
            updateAppliedFilter(StardustFilter())
        }
    }

    private func removeChip(_ chip: StardustFilter.Chip) {
        updateAppliedFilter(appliedFilter.removing(chip))
    }

    private func updateAppliedFilter(_ next: StardustFilter) {
        let normalized = next.normalized() ?? StardustFilter()
        draftFilter = normalized
        guard normalized != appliedFilter else { return }
        appliedFilter = normalized
        filterRevision += 1
    }

    private func hasNextPage(_ data: StardustRecords) -> Bool {
        data.exist_more == true && data.cursor != nil && data.cursor != lastCursor
    }

    private func load(force: Bool = false, nextPage: Bool = false) async {
        let revision = filterRevision
        let filter = appliedFilter
        if nextPage {
            guard loadedFilterRevision == revision, let data = loader.value, hasNextPage(data) else { return }
        }
        let requestedPage = nextPage ? page + 1 : 1
        let cursor = nextPage ? loader.value?.cursor : nil
        let force = force || (nextPage && loader.nextPageError != nil)
        let merge = nextPage ? appendPage(\StardustRecords.records) : nil
        let resource = WebsiteResource.stardust(memberID: memberID, filter: filter, beforeID: cursor)
        if await loader.load(account.website, resource, force: force, appending: merge) != nil,
           filterRevision == revision {
            page = requestedPage
            lastCursor = cursor
            loadedFilterRevision = revision
            if isOwnHistory {
                balanceAtLastLoad = account.user?.stardust
            }
        }
    }
}
