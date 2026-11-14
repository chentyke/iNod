import Foundation

public struct MarkdownTab: Equatable, Sendable {
    public let title: String
    public let markdown: String

    static func parse(_ lines: [String], from start: Int) -> (items: [MarkdownTab], nextIndex: Int)? {
        let opening = lines[start].trimmingCharacters(in: .whitespaces)
        guard let match = opening.firstMatch(of: /^(:{4,})\s+tabs\s*$/) else { return nil }
        let closing = String(match.1)
        var items: [MarkdownTab] = []
        var title: String?
        var body: [String] = []
        var itemClosing: String?
        var codeFence: (character: Character, count: Int)?
        var nestedContainers: [String] = []

        func appendItem() {
            if let title {
                items.append(MarkdownTab(title: title, markdown: body.joined(separator: "\n")))
            }
            title = nil; body = []; itemClosing = nil
        }

        for index in (start + 1)..<lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = codeFence {
                body.append(line)
                if trimmed.prefix(while: { $0 == fence.character }).count >= fence.count,
                   trimmed.allSatisfy({ $0 == fence.character }) { codeFence = nil }
                continue
            }
            if let character = trimmed.first, character == "`" || character == "~" {
                let count = trimmed.prefix(while: { $0 == character }).count
                if count >= 3 { codeFence = (character, count); body.append(line); continue }
            }
            if !nestedContainers.isEmpty {
                body.append(line)
                if trimmed == nestedContainers.last { nestedContainers.removeLast() }
                else if let nested = trimmed.firstMatch(of: /^(:{3,})\s+\S.*$/) {
                    nestedContainers.append(String(nested.1))
                }
                continue
            }
            if trimmed == closing {
                appendItem()
                return items.isEmpty ? nil : (items, index + 1)
            }
            if let item = trimmed.firstMatch(of: /^(:{3,})\s+tab-item\s+(.+)$/), item.1.count < closing.count {
                appendItem()
                title = String(item.2); itemClosing = String(item.1)
            } else if trimmed == itemClosing {
                appendItem()
            } else if title != nil {
                if let nested = trimmed.firstMatch(of: /^(:{3,})\s+\S.*$/) {
                    nestedContainers.append(String(nested.1))
                }
                body.append(line)
            } else if !trimmed.isEmpty {
                return nil
            }
        }
        return nil
    }
}
