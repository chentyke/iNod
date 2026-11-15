import Foundation

public enum HostedImageLinkFormat: String, CaseIterable, Sendable {
    case direct, markdown, html, bbcode

    public var title: String {
        switch self {
        case .direct: "直链"
        case .markdown: "Markdown"
        case .html: "HTML"
        case .bbcode: "BBCode"
        }
    }

    public func text(for url: URL) -> String {
        let address = url.absoluteString
        switch self {
        case .direct: return address
        case .markdown: return "![图片](<\(address)>)"
        case .html:
            let escaped = address.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            return "<img src=\"\(escaped)\" alt=\"图片\">"
        case .bbcode: return "[img]\(address)[/img]"
        }
    }
}
