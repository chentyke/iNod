import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct AccountDataView<Value: Decodable, Content: View>: View {
    let value: Value?
    let error: LoadFailure?
    let isBusy: Bool
    let margins: ReadableMargin
    let scroller: ReadableScroller
    let retry: () async -> Void
    @ViewBuilder var content: (Value) -> Content
    @State private var showsVerification = false
    @Environment(AccountSession.self) private var account

    init(value: Value?, error: LoadFailure?, isBusy: Bool,
         margins: ReadableMargin = .replacesInset, in scroller: ReadableScroller = .list,
         retry: @escaping () async -> Void,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.value = value
        self.error = error
        self.isBusy = isBusy
        self.margins = margins
        self.scroller = scroller
        self.retry = retry
        self.content = content
    }

    init(loader: ResourceLoader<Value>,
         margins: ReadableMargin = .replacesInset, in scroller: ReadableScroller = .list,
         retry: @escaping () async -> Void,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.init(value: loader.value, error: loader.error, isBusy: loader.loading || loader.updating,
                  margins: margins, in: scroller, retry: retry, content: content)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let value = value {
                if let error = error {
                    LoadFailureBanner(failure: error, isRetrying: isBusy) { Task { await retry() } }
                        .padding(.horizontal, SeekLayout.gutter).padding(.vertical, 8)
                        .readableColumn()
                }
                content(value)
            } else if let error = error {
                LoadFailureView(failure: error, isRetrying: isBusy,
                                offersWebsite: account.website.needsWebsite || account.signInStatus == .signedOut,
                                retry: { Task { await retry() } }, verify: { showsVerification = true })
            } else {
                ProgressView("正在读取").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .seekCanvas(margins: margins, in: scroller)
        .menuRefreshable(retry)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .hidesTabBarWhenPushed()
        .sheet(isPresented: $showsVerification, onDismiss: { Task { await retry() } }) { WebsiteView(initialURL: NodeSeekRoute.home.url) }
    }
}
