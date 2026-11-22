import Foundation
@preconcurrency import libxml2

public enum ForumSignature {
    /// The thread response (including cached pages) contains an HTML fragment for each signature.
    public static func attributed(_ html: String, baseURL: URL) -> AttributedString {
        let byteCount = html.utf8.count
        guard byteCount > 0, let length = Int32(exactly: byteCount) else { return AttributedString() }
        let options = HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue
        guard let document = htmlReadMemory(html, length, nil, "UTF-8", Int32(options)) else {
            return AttributedString()
        }
        defer { xmlFreeDoc(document) }

        var result = AttributedString()
        if let root = xmlDocGetRootElement(document) {
            append(root, baseURL: baseURL, attributes: AttributeContainer(), preservesWhitespace: false, to: &result)
        }
        while result.characters.last?.isWhitespace == true {
            result.characters.removeLast()
        }
        return result
    }

    private static func append(_ node: xmlNodePtr, baseURL: URL, attributes: AttributeContainer,
                               preservesWhitespace: Bool, to result: inout AttributedString) {
        if node.pointee.type == XML_TEXT_NODE, let content = node.pointee.content {
            var text = String(cString: content)
            if !preservesWhitespace {
                text = text.replacingOccurrences(of: #"[ \t\r\n\f]+"#, with: " ", options: .regularExpression)
                if text.first == " ", result.characters.last?.isWhitespace != false { text.removeFirst() }
            }
            result += AttributedString(text, attributes: attributes)
            return
        }

        guard node.pointee.type == XML_ELEMENT_NODE, let name = node.pointee.name else { return }
        let tag = String(cString: name)
        var attributes = attributes
        var intent = attributes.inlinePresentationIntent ?? []
        switch tag {
        case "head", "script", "style", "template": return
        case "br": result += AttributedString("\n"); return
        case "a": attributes.link = link(in: node, baseURL: baseURL)
        case "strong", "b", "h1", "h2", "h3", "h4", "h5", "h6": intent.insert(.stronglyEmphasized)
        case "em", "i": intent.insert(.emphasized)
        case "s", "del": intent.insert(.strikethrough)
        case "code", "pre": intent.insert(.code)
        default: break
        }
        if !intent.isEmpty { attributes.inlinePresentationIntent = intent }

        let isBlock = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "pre", "blockquote", "hr"].contains(tag)
        if isBlock { startLine(in: &result) }
        var child = node.pointee.children
        while let current = child {
            append(current, baseURL: baseURL, attributes: attributes,
                   preservesWhitespace: preservesWhitespace || tag == "pre", to: &result)
            child = current.pointee.next
        }
        if isBlock { startLine(in: &result) }
    }

    private static func startLine(in result: inout AttributedString) {
        if result.characters.last == " " { result.characters.removeLast() }
        if let last = result.characters.last, last != "\n" { result += AttributedString("\n") }
    }

    private static func link(in node: xmlNodePtr, baseURL: URL) -> URL? {
        guard let href = xmlGetProp(node, "href") else { return nil }
        defer { xmlFree(href) }
        let target = String(cString: href).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, let url = URL(string: target, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return nil }
        return url
    }
}
