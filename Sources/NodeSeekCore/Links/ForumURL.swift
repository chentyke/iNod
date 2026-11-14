import Foundation

public enum ForumURL {
    public static func normalized(_ input: String) -> URL? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("www.nodeseek.com/") || value.lowercased().hasPrefix("nodeseek.com/") { value = "https://" + value }
        guard let url = URL(string:value,relativeTo:NodeSeekRoute.origin)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),["http","https"].contains(scheme),
              ["nodeseek.com","www.nodeseek.com"].contains(url.host()?.lowercased() ?? ""),
              url.user == nil,url.password == nil,
              url.port == nil || url.port == (scheme == "http" ? 80 : 443),
              var components = URLComponents(url:url,resolvingAgainstBaseURL:false) else { return nil }
        components.scheme = "https"; components.host = "www.nodeseek.com"; components.port = nil
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }
}
