import SwiftUI

struct LoadMoreRow: View {
    let error: String?
    var isEnabled = true
    let load: () async -> Void
    @State private var hasAppearedOnScreen = false

    var body: some View {
        Group {
            if let error {
                VStack(spacing: 8) {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.borderless)
                        .disabled(!isEnabled)
                }
            } else {
                ProgressView("正在加载")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .listRowSeparator(.hidden)
        .onScrollVisibilityChange(threshold: 0.1) { isVisible in
            if isVisible { hasAppearedOnScreen = true }
        }
        .task(id: hasAppearedOnScreen && isEnabled) {
            guard hasAppearedOnScreen, isEnabled, error == nil, !Task.isCancelled else { return }
            await load()
        }
    }
}
