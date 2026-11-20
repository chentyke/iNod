#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacUpdatePrompts: ViewModifier {
    let updater: MacUpdater
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert(updater.prompt?.title ?? "", isPresented: Binding(
            get: { updater.prompt != nil },
            set: { if !$0 { updater.prompt = nil } }
        ), presenting: updater.prompt) { prompt in
            switch prompt {
            case .available(let release):
                Button("打开下载页") { openURL(release.page) }
                Button("稍后", role: .cancel) { }
            case .ready:
                Button("重启并安装") { Task { await updater.install() } }
                Button("稍后", role: .cancel) { updater.discard() }
            case .current, .checkFailed, .downloadFailed, .installFailed:
                Button("好", role: .cancel) { }
            }
        }
    }
}
#endif
