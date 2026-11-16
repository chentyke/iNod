import NodeSeekClient
import SwiftUI
import WebKit

/// The website inside the app, for the site's human check only. It shares the app's cookies, so finishing
/// the check here unblocks the app's own requests; every other page of the site opens in the reader's browser.
struct WebsiteView: View {
    @State private var page = SitePage.make()
    var initialURL: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSession.self) private var account

    var body: some View {
        NavigationStack {
            WebView(page)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .overlay(alignment: .top) {
                    if page.isLoading { ProgressView(value: page.estimatedProgress).tint(.seekGreen) }
                }
                .navigationTitle("NodeSeek 官网")
                .navigationSubtitle(page.url?.host() ?? "www.nodeseek.com")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            Task {
                                await account.synchronize(from: page)
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("重新加载", systemImage: "arrow.clockwise") { page.reload() }
                    }
                }
                .task {
                    if let initialURL { page.load(initialURL) }
                }
                .onChange(of: page.isLoading) { _, loading in
                    if !loading { Task { await account.synchronize(from: page) } }
                }
        }
        .onDisappear {
            account.website.invalidate()
            Task { await account.refresh(force: true) }
        }
    }
}
