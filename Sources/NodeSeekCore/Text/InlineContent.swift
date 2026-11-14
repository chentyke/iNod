import Foundation

public enum InlineContent: Equatable, Sendable {
    case text(String)
    case sticker(ForumSticker)

    private static let regex = try? NSRegularExpression(pattern: #"`+[^`]*`+|https?://[^\s)]+|:[a-z]+\d+:"#)

    public static func parse(_ text: String) -> [InlineContent] {
        guard let regex else { return [.text(text)] }
        let source = text as NSString
        var result: [InlineContent] = []
        var offset = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let value = source.substring(with: match.range)
            guard value.hasPrefix(":"), let sticker = ForumSticker.named(String(value.dropFirst().dropLast())) else { continue }
            if match.range.location > offset {
                result.append(.text(source.substring(with: NSRange(location: offset, length: match.range.location - offset))))
            }
            result.append(.sticker(sticker))
            offset = NSMaxRange(match.range)
        }
        if offset < source.length { result.append(.text(source.substring(from: offset))) }
        return result.isEmpty ? [.text(text)] : result
    }
}
