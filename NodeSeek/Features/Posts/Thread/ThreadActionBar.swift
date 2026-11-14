import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct ThreadActionBar: View {
    let post: PostSummary
    let canReply: Bool
    let showsReply: Bool
    let isOpeningReply: Bool
    let isCollected: Bool
    let isUpdatingCollection: Bool
    let onCollection: () -> Void
    let onReply: () -> Void
    @Environment(AccountSession.self) private var account

    private var replyTitle: String {
        return account.signInStatus == .signedOut ? "登录后回复" : "写回复"
    }

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 12) {
                if showsReply {
                    Button(action: onReply) {
                        Label(replyTitle, systemImage: "square.and.pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.seekOnInk)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .padding(.horizontal, 16)
                            .lineLimit(2)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canReply || isOpeningReply)
                    .glassEffect(.regular.tint(Color.seekInk).interactive(), in: .capsule)
                    .opacity(canReply ? 1 : 0.55)
                } else {
                    Spacer(minLength: 0)
                }

                Button(action: onCollection) {
                    Image(systemName: isCollected ? "bookmark.fill" : "bookmark")
                        .font(.title3.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(.primary)
                        .frame(width: 54, height: 54)
                        .contentShape(.circle)
                }
                .accessibilityLabel(isCollected ? "取消收藏" : "收藏")
                .buttonStyle(.plain)
                .disabled(isUpdatingCollection)
                .glassEffect(.regular.tint(Color.seekGreen.opacity(isCollected ? 0.4 : 0.18)).interactive(), in: .circle)

                ShareLink(item: post.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(.primary)
                        .frame(width: 50, height: 50)
                        .contentShape(.circle)
                }
                .accessibilityLabel("分享帖子")
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Color.blue.opacity(0.2)).interactive(), in: .circle)
            }
        }
    }
}
