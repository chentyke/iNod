import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct AccountDataView<Value: Decodable, Content: View>: View {
    let value: Value?
    let error: String?
    let isBusy: Bool
    let retry: () async -> Void
    @ViewBuilder var content: (Value) -> Content
    @State private var showsWebsite = false
    @Environment(AccountSession.self) private var account

    init(value: Value?, error: String?, isBusy: Bool, retry: @escaping () async -> Void,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.value = value
        self.error = error
        self.isBusy = isBusy
        self.retry = retry
        self.content = content
    }

    init(loader: AccountLoader<Value>, retry: @escaping () async -> Void,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.init(value: loader.value, error: loader.error, isBusy: loader.isLoading || loader.isUpdating,
                  retry: retry, content: content)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Button("重试", systemImage: "arrow.clockwise") { Task { await retry() } }
                            .disabled(isBusy)
                        if account.website.needsWebsite || account.signInStatus == .signedOut {
                            Button("打开官网完成登录或验证", systemImage: "globe") { showsWebsite = true }
                        }
                    }.font(.subheadline)
                }.seekCard().padding(16)
            }
            if let value = value { content(value) }
            else if error == nil {
                ProgressView("正在读取").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { Spacer() }
        }
        .seekCanvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showsWebsite, onDismiss: { Task { await retry() } }) { WebsiteView(initialURL: NodeSeekRoute.home.url) }
    }
}
