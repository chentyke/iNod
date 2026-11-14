import NodeSeekCore
import SwiftUI

struct ThreadAuthorBar: View {
    let post: PostSummary
    let detail: PostDetail?

    private var authorName: String { detail?.op.name ?? post.author }
    private var authorID: Int? { detail?.op.uid ?? post.authorID }
    private var avatarURL: URL? { detail?.op.avatarURL ?? post.avatarURL }

    var body: some View {
        HStack(spacing: 10) {
            if let authorID {
                NavigationLink(value: MemberDestination.profile(authorID)) {
                    authorLabel
                        .padding(.leading, 4)
                        .padding(.trailing, 12)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .labelStyle(.titleAndIcon)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("查看 \(authorName) 的主页")
            } else if !authorName.isEmpty {
                authorLabel
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var authorLabel: some View {
        Label {
            Text(authorName)
                .font(.headline.bold())
                .foregroundStyle(Color.seekInk)
                .lineLimit(1)
        } icon: {
            AvatarView(name: authorName, url: avatarURL, size: 36)
        }
        .labelStyle(.titleAndIcon)
        .frame(minHeight: 44)
    }
}
