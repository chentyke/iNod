/// The replies read so far, starting at the page a link or notification opened.
public struct ThreadPages: Sendable {
    public private(set) var detail: PostDetail
    public private(set) var loaded: ClosedRange<Int>
    public private(set) var total: Int

    public init(_ detail: PostDetail) {
        self.detail = detail
        loaded = detail.postPage...detail.postPage
        total = max(detail.postPage, detail.postPageCount)
    }

    public func canLoad(_ page: Int) -> Bool {
        guard page > 0, page <= total else { return false }
        if page < loaded.lowerBound { return page == loaded.lowerBound - 1 }
        return page - 1 == loaded.upperBound
    }

    public mutating func apply(_ reaction: CommentReaction, count: Int, to commentID: Int) {
        for index in detail.comments.indices where detail.comments[index].id == commentID {
            detail.comments[index].apply(reaction, count: count)
        }
    }

    /// Returns the newly inserted comments, including an empty list for an all-duplicate page.
    public mutating func merge(_ page: PostDetail, requestedPage: Int) -> [ForumComment]? {
        guard page.postId == detail.postId, page.postPage == requestedPage, canLoad(requestedPage) else { return nil }
        var ids = Set(detail.comments.map(\.id))
        let added = page.comments.filter { ids.insert($0.id).inserted }
        if requestedPage < loaded.lowerBound {
            detail.comments.insert(contentsOf: added, at: 0)
            loaded = requestedPage...loaded.upperBound
        } else {
            detail.comments.append(contentsOf: added)
            loaded = loaded.lowerBound...requestedPage
        }
        total = max(loaded.upperBound, page.postPageCount)
        return added
    }
}
