import NodeSeekClient
import NodeSeekCore
import SwiftUI

struct InboxList<Item: Identifiable, LeadingContent: View, Row: View>: View {
    let items: [Item]?
    let emptyTitle: String
    let emptySymbol: String
    let error: String?
    let isBusy: Bool
    let reload: () async -> Void
    let leadingContent: LeadingContent
    @ViewBuilder let row: (Item) -> Row
    @Environment(AccountSession.self) private var account
    @State private var showsWebsite = false

    var body: some View {
        List {
            leadingContent
            if let items, !items.isEmpty {
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        retryActions
                    }
                    .padding(.vertical, 8)
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
                    ContentUnavailableView {
                        Label("暂时无法加载", systemImage: "exclamationmark.circle")
                    } description: {
                        Text(error)
                    } actions: {
                        retryActions
                    }
                } else if items == nil || isBusy {
                    ProgressView().accessibilityLabel("正在加载")
                } else {
                    ContentUnavailableView(emptyTitle, systemImage: emptySymbol)
                        .allowsHitTesting(false)
                }
            }
        }
        .sheet(isPresented: $showsWebsite, onDismiss: { Task { await reload() } }) {
            WebsiteView(initialURL: NodeSeekRoute.home.url)
        }
    }

    private var retryActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("重试") { Task { await reload() } }
                .disabled(isBusy)
            if account.website.needsWebsite || account.signInStatus == .signedOut {
                Button("打开官网") { showsWebsite = true }
            }
        }
        .buttonStyle(.borderless)
    }
}
