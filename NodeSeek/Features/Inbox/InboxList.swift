import NodeSeekClient
import NodeSeekCore
import SwiftUI

struct InboxList<Item: Identifiable, LeadingContent: View, Row: View>: View {
    let items: [Item]?
    let emptyTitle: String
    let emptySymbol: ImageResource
    let error: LoadFailure?
    let isBusy: Bool
    let reload: () async -> Void
    let isSelected: Bool
    let leadingContent: LeadingContent
    @ViewBuilder let row: (Item) -> Row
    @Environment(AccountSession.self) private var account
    @State private var isRefreshing = false
    @State private var showsVerification = false

    var body: some View {
        List {
            leadingContent
            if let items, !items.isEmpty {
                if let error {
                    // Keep what's already listed and note the failure above it.
                    Section {
                        LoadFailureBanner(failure: error, isRetrying: isBusy) { Task { await reload() } }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(items, content: row)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.seekHairline)
            } else {
                // Keep the list scrollable when neither a search field nor inbox rows are visible.
                Color.clear
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
            }
        }
        .listStyle(.plain)
        .accessibilityHidden(!isSelected)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .readableContentMargins()
        .refreshable {
            isRefreshing = true
            defer { isRefreshing = false }
            await reload()
        }
        .background {
            if isSelected {
                Color.clear.menuRefreshable { await reload() }
            }
        }
        .overlay {
            if items?.isEmpty != false, !isRefreshing {
                if let error {
                    LoadFailureView(failure: error, isRetrying: isBusy,
                                    offersWebsite: account.website.needsWebsite || account.signInStatus == .signedOut,
                                    retry: { Task { await reload() } }, verify: { showsVerification = true })
                } else if items == nil || isBusy {
                    ProgressView().accessibilityLabel("正在加载")
                } else {
                    ContentUnavailableView(emptyTitle, image: emptySymbol)
                        .allowsHitTesting(false)
                }
            }
        }
        .sheet(isPresented: $showsVerification, onDismiss: { Task { await reload() } }) {
            WebsiteView(initialURL: NodeSeekRoute.home.url)
        }
    }
}
