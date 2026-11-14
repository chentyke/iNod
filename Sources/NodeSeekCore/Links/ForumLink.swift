import Foundation

public enum ForumLink: Equatable, Sendable {
    case native(ForumLinkDestination)
    case website(URL)

    static func mentionURL(name: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "nsapp"
        parts.host = "mention"
        parts.queryItems = [URLQueryItem(name: "name", value: name)]
        return parts.url!
    }

    public static func parse(_ input: String) -> ForumLink? { parse(input,remainingRedirects:3) }
    private static func parse(_ input: String,remainingRedirects: Int) -> ForumLink? {
        if let parts = URLComponents(string: input), parts.scheme == "nsapp", parts.host == "mention",
           let name = parts.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty {
            return .native(.mention(name))
        }
        guard let url = ForumURL.normalized(input),let parts = URLComponents(url:url,resolvingAgainstBaseURL:false) else { return nil }
        let query = Dictionary(parts.queryItems?.map { ($0.name,$0.value ?? "") } ?? [],uniquingKeysWith:{ first,_ in first })
        if url.path == "/jump",let target = query["to"],remainingRedirects > 0 {
            // The official renderer uses /jump?to= for redirect links. External targets remain external.
            return parse(target,remainingRedirects:remainingRedirects-1)
        }
        if let post = PostAddress(url.absoluteString) { return .native(.post(post)) }
        if let member = MemberAddress.parse(url.absoluteString) { return .native(.member(id:member,section:url.fragment)) }
        if let draw = LuckyDraw(url:url) { return .native(.lucky(draw)) }
        let sort = FeedSort(rawValue:query["sortBy"] ?? "") ?? .replyTime
        if url.path == "/" { return .native(.feed(category:"",sort:sort)) }
        if let match = url.path.firstMatch(of:/^\/categories\/([a-zA-Z0-9_-]+)\/?$/) {
            return .native(.feed(category:String(match.1),sort:sort))
        }
        if url.path == "/search",query["page"] == nil || query["page"] == "1" { return .native(.search(query:query["q"] ?? "",category:query["category"] ?? "",sort:sort)) }
        if url.path == "/award" { return .native(.recommended) }
        return .website(url)
    }
}
