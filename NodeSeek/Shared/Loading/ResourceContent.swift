import NodeSeekCore
import SwiftUI

struct ResourceContent<Value: Decodable, Content: View>: View {
    let loader: ResourceLoader<Value>
    var websiteURL = NodeSeekRoute.home.url
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content
    @State private var showsWebsite = false
    private var isBusy: Bool { loader.loading || loader.updating }
    var body: some View {
        VStack(spacing: 0) {
            if let value = loader.value {
                if let error = loader.error {
                    LoadFailureBanner(failure: error, isRetrying: isBusy) { Task { await retry() } }
                        .padding(.horizontal, SeekLayout.gutter).padding(.vertical, 8)
                        .readableColumn()
                }
                content(value)
            } else if let error = loader.error {
                LoadFailureView(failure: error, isRetrying: isBusy, offersWebsite: true,
                                retry: { Task { await retry() } }, openWebsite: { showsWebsite = true })
            } else {
                ProgressView("正在读取").frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.seekCanvas().navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar).toolbar(.hidden,for:.tabBar)
        .sheet(isPresented:$showsWebsite,onDismiss:{ Task { await retry() } }) { WebsiteView(initialURL: websiteURL) }
    }
}
