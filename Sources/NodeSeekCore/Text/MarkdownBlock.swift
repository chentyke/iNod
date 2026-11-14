import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    case text(String), heading(String), code(String), quote(String)
    case image(alt: String, url: URL)
    case list(items: [String], ordered: Bool)
    case table([[String]])
    case divider
    case vote(Int)
    case stardust(StardustRequest)
    case tabs([MarkdownTab])

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var result: [MarkdownBlock] = [], text: [String] = []
        var index = 0
        func flush() {
            let value = text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result.append(.text(value)) }; text = []
        }
        func cells(_ line: String) -> [String] {
            var parts = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.first == "" { parts.removeFirst() }; if parts.last == "" { parts.removeLast() }
            return parts
        }
        let headingRule = /^#{1,6}\s+(.+)$/
        let tableDividerRule = /^:?-{3,}:?$/
        let listItemRule = /^(?:([-*+])|\d+[.)])\s+(.+)$/
        let voteRule = /^(?:\[.*\]\()?nsapp:\/\/vote\?id=(\d+)\)?$/
        let embeddedContentRule = /!\[(?<alt>[^\]]*)\]\((?:<(?<bracketed>https?:\/\/[^<>]+)>|(?<bare>https?:\/\/[^\s)]+))\)|(?:\[[^\]]*\]\()?(?<widget>nsapp:\/\/(?:vote|stardust-receive)\?[^\s)]+)\)?/
        while index < lines.count {
            let line = lines[index], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("::::"), let tabs = MarkdownTab.parse(lines, from: index) {
                flush(); result.append(.tabs(tabs.items)); index = tabs.nextIndex; continue
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush(); let fence = String(trimmed.prefix(3)); var code: [String] = []; index += 1
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { code.append(lines[index]); index += 1 }
                result.append(.code(code.joined(separator: "\n")))
            } else if let match = trimmed.firstMatch(of: headingRule) {
                flush(); result.append(.heading(String(match.1)))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flush(); result.append(.divider)
            } else if trimmed.hasPrefix(">") {
                flush(); var quote: [String] = []
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); index += 1
                }
                result.append(.quote(quote.joined(separator: "\n"))); continue
            } else if index + 1 < lines.count, line.contains("|"), cells(lines[index + 1]).count > 1,
                      cells(lines[index + 1]).allSatisfy({ $0.firstMatch(of: tableDividerRule) != nil }) {
                flush(); var rows = [cells(line)]; index += 2
                while index < lines.count && lines[index].contains("|") && !lines[index].isEmpty { rows.append(cells(lines[index])); index += 1 }
                result.append(.table(rows)); continue
            } else if let match = trimmed.firstMatch(of: listItemRule) {
                flush(); let ordered = match.1 == nil; var items: [String] = []
                while index < lines.count, let item = lines[index].trimmingCharacters(in: .whitespaces).firstMatch(of: listItemRule), (item.1 == nil) == ordered {
                    items.append(String(item.2)); index += 1
                }
                result.append(.list(items: items, ordered: ordered)); continue
            } else if let request = StardustRequest(trimmed) {
                flush(); result.append(.stardust(request))
            } else if let match = trimmed.firstMatch(of: voteRule), let id = Int(match.1), id > 0 {
                flush(); result.append(.vote(id))
            } else if trimmed.isEmpty { flush() }
            else {
                let images = line.matches(of: embeddedContentRule)
                if images.isEmpty { text.append(line) }
                else {
                    var start = line.startIndex
                    for match in images {
                        text.append(String(line[start..<match.range.lowerBound])); flush()
                        if let image = match.bracketed ?? match.bare, let url = URL(string: String(image)) {
                            result.append(.image(alt: String(match.alt ?? ""), url: url))
                        } else if let source = match.widget {
                            let value = String(source)
                            if let request = StardustRequest(value) { result.append(.stardust(request)) }
                            else if let url = URLComponents(string:value),url.host == "vote",let raw = url.queryItems?.first(where:{ $0.name == "id" })?.value,let id = Int(raw),id > 0 { result.append(.vote(id)) }
                            else { result.append(.text(value)) }
                        }
                        start = match.range.upperBound
                    }
                    text.append(String(line[start...]))
                }
            }
            index += 1
        }
        flush(); return result
    }
}
