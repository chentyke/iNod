import SwiftUI

struct ThreadCommentsLoader: View {
    let page: Int
    let loadingEarlier: Bool
    let error: String?
    let canLoad: Bool
    let onLoad: () -> Void
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 12) {
            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重试加载评论", action: onLoad)
                    .buttonStyle(.seekPill(primary: false))
                    .disabled(!canLoad)
            } else {
                ProgressView(loadingEarlier ? "正在加载前面的评论" : "正在加载更多评论")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
        .task(id: isVisible && canLoad ? page : nil) {
            guard isVisible, canLoad, error == nil, !Task.isCancelled else { return }
            onLoad()
        }
    }
}
