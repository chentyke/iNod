import Foundation

public enum NodeSeekRoute: Sendable {
    case feed(category: String, sort: FeedSort, page: Int)
    case search(query: String, category: String, sort: FeedSort, page: Int)
    case thread(id: Int, page: Int)
    case home
    case recommended(page: Int)
    /// A section of the website's settings page, such as `contact` or `security`.
    case settings(section: String)
    /// The website's sign-in page, which also leads to signing up and resetting a password.
    case signIn

    public static let origin = URL(string: "https://www.nodeseek.com")!

    public var url: URL {
        var parts = URLComponents(url: Self.origin, resolvingAgainstBaseURL: false)!
        switch self {
        case let .feed(category, sort, page):
            let page = max(1, page)
            parts.path = category.isEmpty ? (page == 1 ? "/" : "/page-\(page)") : "/categories/\(category)" + (page == 1 ? "" : "/page-\(page)")
            parts.queryItems = [URLQueryItem(name: "sortBy", value: sort.rawValue)]
        case let .search(query, category, sort, page):
            parts.path = "/search"
            parts.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: String(max(1, page))),
                URLQueryItem(name: "sortBy", value: sort.rawValue)
            ]
            if !category.isEmpty { parts.queryItems?.append(URLQueryItem(name: "category", value: category)) }
        case let .thread(id, page):
            parts.path = "/post-\(id)-\(max(1, page))"
        case .home:
            parts.path = "/"
        case .recommended(let page):
            parts.path = max(1,page) == 1 ? "/award" : "/award/page-\(max(1,page))"
        case .settings(let section):
            parts.path = "/setting"
            parts.fragment = section
        case .signIn:
            parts.path = "/signIn.html"
        }
        // Website query parsing treats a literal + as a space.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }
}
