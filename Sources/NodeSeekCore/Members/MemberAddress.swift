import Foundation

public enum MemberAddress {
    public static func parse(_ input: String) -> Int? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty, input.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int(input), id > 0 { return id }
        guard let url = URL(string: input), url.scheme == "https",
              ["www.nodeseek.com", "nodeseek.com"].contains(url.host()?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2, parts[0] == "space" else { return nil }
        let value = String(parts[1])
        guard value.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int(value), id > 0 else { return nil }
        return id
    }
}
