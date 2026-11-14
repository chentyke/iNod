public enum ForumLinkDestination: Hashable, Sendable {
    case post(PostAddress)
    case member(id: Int,section: String?)
    case mention(String)
    case feed(category: String,sort: FeedSort)
    case search(query: String,category: String,sort: FeedSort)
    case recommended
    case lucky(LuckyDraw)
}
