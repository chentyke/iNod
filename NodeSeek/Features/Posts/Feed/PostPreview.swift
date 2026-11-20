import NodeSeekCore
import NodeSeekClient
import SwiftUI

/// Long-press preview of a post: the opening floor, read from the same cache the thread uses.
struct PostPreview: View {
    @Environment(AccountSession.self) private var account
    let post: PostSummary
    @AppStorage("showsBlockedContent") private var showsBlocked = false
    @State private var original: ForumComment?
    @State private var replies: [PostPreviewReply] = []
    @State private var error: (any Error)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AvatarView(name: post.author, url: post.avatarURL, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.author).font(.subheadline.weight(.semibold)).foregroundStyle(Color.seekInk)
                    if !post.category.isEmpty {
                        Text(post.category).font(.caption).foregroundStyle(Color.categoryTint(post.categoryKey))
                    }
                }
                .lineLimit(1)
            }
            Text(post.title).font(.title3.bold()).foregroundStyle(Color.seekInk)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Group {
                if let original, showsBlocked || !original.blocked {
                    let visibleReplies = showsBlocked ? replies : replies.filter { !$0.blocked }
                    VStack(alignment: .leading, spacing: 16) {
                        ForumMarkdown(markdown: original.markdown)
                            .font(.callout).foregroundStyle(Color.seekInk)
                        if !visibleReplies.isEmpty {
                            Divider()
                            ForEach(visibleReplies) { reply in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reply.author).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(ForumText.attributed(reply.snippet, baseURL: post.url)).font(.subheadline).foregroundStyle(Color.seekInk).lineLimit(3)
                                }
                            }
                        }
                    }
                } else if let error {
                    Label(LoadFailure(error).message, image: error is PostAccessError ? .inkRestrictedPost : LoadFailure(error).inkIcon)
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
            }
            PostMetadata(post: post)
        }
        .padding(20)
        .frame(width: 360, height: 480, alignment: .topLeading)
        .background(Color.seekCard)
        .environment(\.forumDocumentURL, post.url)
        .task(id: showsBlocked) {
            let includeBlocked = showsBlocked
            original = nil
            replies = []
            error = nil
            do {
                let detail = try await account.website.thread(id: post.id, page: 1, includeBlocked: includeBlocked, summary: post)
                try Task.checkCancellation()
                guard showsBlocked == includeBlocked else { return }
                original = detail.comments.first { $0.floorIndex == 0 }
                replies = PostPreviewReply.select(from: detail.replies)
                if original == nil { error = SiteError.message("没有找到正文") }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, showsBlocked == includeBlocked else { return }
                self.error = error
            }
        }
    }
}
