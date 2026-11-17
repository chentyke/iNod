import NodeSeekCore

/// Destinations registered in the forum navigation stack.
enum AppDestination: Hashable {
    case post(PostSummary, page: Int, floor: Int?)
    case memberSearch
    case communityTools
    case recommended
    case luckyDraw
    case networkQuality
    case deviceBenchmark
    case rulings(recordID: Int?)
    case directory(providers: Bool)
    case siteArticle(path: String, title: String)
    case connections(follows: Bool, userID: Int)
    case invitations(userID: Int)
    case imageLibrary(userID: Int)
    case stardustTransfer(userID: Int, recipient: MessageRecipient?)
}
