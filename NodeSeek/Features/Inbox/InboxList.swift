import NodeSeekClient
import NodeSeekCore
import SwiftUI

struct InboxList<Item: Identifiable, LeadingContent: View, Row: View>: View {
    let items: [Item]?
    let emptyTitle: String
    let emptySymbol: String
    let error: LoadFailure?
    let isBusy: Bool
    let reload: () async -> Void
    let leadingContent: LeadingContent
    @ViewBuilder let row: (Item) -> Row
    @Environment(AccountSession.self) private var account
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
                    .listRowInsets(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
            }
        }
        .listStyle(.insetGrouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .contentMargins(.top, 4, for: .scrollContent)
        .readableContentMargins()
        .refreshable { await reload() }
        .overlay {
            if items?.isEmpty != false {
                if let error {
                    LoadFailureView(failure: error, isRetrying: isBusy,
                                    offersWebsite: account.website.needsWebsite || account.signInStatus == .signedOut,
                                    retry: { Task { await reload() } }, verify: { showsVerification = true })
                } else if items == nil || isBusy {
                    ProgressView().accessibilityLabel("正在加载")
                } else {
                    ContentUnavailableView(emptyTitle, systemImage: emptySymbol)
                        .allowsHitTesting(false)
                }
            }
        }
        .sheet(isPresented: $showsVerification, onDismiss: { Task { await reload() } }) {
            WebsiteView(initialURL: NodeSeekRoute.home.url)
        }
    }
}
