import Foundation

public enum ForumText {
    private static let linkDetector = try? NSDataDetector(types:NSTextCheckingResult.CheckingType.link.rawValue)
    private static let referencePattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_@#])(?:@([\p{L}\p{N}_-]+)|#([0-9]+)(?![A-Za-z0-9_]|\.[0-9]))"#
    )

    public static func attributed(_ source: String,baseURL: URL = NodeSeekRoute.origin,markdown: Bool = true) -> AttributedString {
        var result = markdown ? ((try? AttributedString(markdown:source,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace),baseURL:baseURL)) ?? AttributedString(source)) : AttributedString(source)
        for run in Array(result.runs) {
            if let link = run.link,let resolved = URL(string:link.relativeString,relativeTo:baseURL)?.absoluteURL {
                result[run.range].link = resolved
            }
        }
        let text = String(result.characters)
        func addLink(_ url: URL, in match: NSRange) {
            guard let range = Range(match,in:text),
                  let lower = AttributedString.Index(range.lowerBound,within:result),let upper = AttributedString.Index(range.upperBound,within:result) else { return }
            let bounds = lower..<upper
            guard result[bounds].runs.allSatisfy({ $0.link == nil && $0.inlinePresentationIntent?.contains(.code) != true }) else { return }
            result[bounds].link = url
        }
        let range = NSRange(text.startIndex..<text.endIndex,in:text)
        for match in linkDetector?.matches(in:text,range:range) ?? [] {
            if let url = match.url { addLink(url, in: match.range) }
        }
        if markdown, let post = PostAddress(baseURL.absoluteString) {
            for match in referencePattern.matches(in: text, range: range) {
                if let name = Range(match.range(at: 1), in: text) {
                    addLink(ForumLink.mentionURL(name: String(text[name])), in: match.range)
                } else if let number = Range(match.range(at: 2), in: text), let floor = Int(text[number]) {
                    addLink(PostAddress.floorURL(postID: post.id, floor: floor), in: match.range)
                }
            }
        }
        return result
    }
}
