import NodeSeekCore
import SwiftUI

struct ResourceContent<Value: Decodable, Content: View>: View {
    let loader: ResourceLoader<Value>
    var websiteURL = NodeSeekRoute.home.url
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content
    @State private var showsWebsite = false
    var body: some View {
        VStack(spacing: 0) {
            if let error = loader.error {
                VStack(alignment:.leading,spacing:8) {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Button("重试",systemImage:"arrow.clockwise") { Task { await retry() } }.disabled(loader.loading || loader.updating)
                        Button("打开官网",systemImage:"globe") { showsWebsite = true }
                    }.font(.subheadline)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(20).background(Color.seekSurface)
            }
            if let value = loader.value { content(value) }
            else if loader.error == nil { ProgressView("正在读取").frame(maxWidth:.infinity,maxHeight:.infinity) }
            else { Spacer() }
        }.seekCanvas().navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar).toolbar(.hidden,for:.tabBar)
        .sheet(isPresented:$showsWebsite,onDismiss:{ Task { await retry() } }) { WebsiteView(initialURL: websiteURL) }
    }
}
