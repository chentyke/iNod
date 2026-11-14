import Foundation

public struct PostAddress: Sendable, Hashable {
    public let id: Int
    public let page: Int
    public let floor: Int?

    public static func page(forFloor floor: Int) -> Int {
        floor <= 10 ? 1 : (floor - 1) / 10 + 1
    }

    public static func floorURL(postID: Int, floor: Int) -> URL {
        let pageURL = NodeSeekRoute.thread(id: postID, page: page(forFloor: floor)).url
        var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)!
        parts.fragment = String(floor)
        return parts.url!
    }

    public init?(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(value), id > 0 { self.id = id; page = 1; floor = nil; return }
        guard let url = ForumURL.normalized(value),
              let match = url.path.firstMatch(of: /^\/post-(\d+)(?:-(\d+))?\/?$/),
              let id = Int(match.1), id > 0, let page = Int(match.2 ?? "1"), page > 0 else { return nil }
        self.id = id; self.page = page; floor = url.fragment.flatMap(Int.init)
    }
    public var summary: PostSummary { PostSummary(id: id, title: "帖子", author: "", avatar: "", category: "", categoryKey: "", views: 0, replies: 0, activityDate: "", pinned: false) }
}
