import SwiftUI

struct ThreadCommentsLoader: View {
    let page: Int
    let error: String?
    let onLoad: () -> Void
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 12) {
            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重试加载评论", action: onLoad)
                    .buttonStyle(.seekPill(primary: false))
            } else {
                ProgressView("正在加载更多评论")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
        .task(id: isVisible ? page : nil) {
            guard isVisible, error == nil else { return }
            onLoad()
        }
    }
}
