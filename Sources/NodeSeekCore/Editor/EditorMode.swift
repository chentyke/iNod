public enum EditorMode: Hashable, Sendable {
    case newPost
    case reply(postID: Int)
    case editPost(postID: Int, originalRank: Int)
    case editComment(commentID: Int)

    public var rawValue: String {
        switch self { case .newPost: "new-discussion"; case .reply: "new-comment"; case .editPost: "edit-discussion"; case .editComment: "edit-comment" }
    }
    public var title: String {
        switch self { case .newPost: "发布帖子"; case .reply: "写回复"; case .editPost: "编辑帖子"; case .editComment: "编辑回复" }
    }
    public var editsTitle: Bool {
        switch self { case .newPost, .editPost: true; default: false }
    }
    public var targetID: Int {
        switch self { case .newPost: 0; case .reply(let id), .editPost(let id, _), .editComment(let id): id }
    }
    public func cost(for draft: EditorDraft) -> Int {
        switch self {
        case .newPost: draft.category == "inside" ? 5 : 0
        case .editPost(_, let original): draft.rank == 255 && original != 255 ? 10 : 0
        default: 0
        }
    }
}
