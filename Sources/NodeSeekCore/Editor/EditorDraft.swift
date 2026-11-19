import Foundation

public struct EditorDraft: Codable, Equatable, Sendable {
    public var title: String
    public var content: String
    public var category: String
    public var rank: Int
    public init(title: String = "", content: String = "", category: String = "daily", rank: Int = 0) {
        self.title = title; self.content = content; self.category = category; self.rank = rank
    }
    public mutating func appendHostedImage(_ url: URL) {
        content += "\n\(HostedImageLinkFormat.markdown.text(for: url))\n"
    }

    /// Pull out the image lines appended by the photo picker, preserving other Markdown and whitespace.
    public mutating func removeTrailingHostedImages() -> [URL] {
        var images: [URL] = []
        let prefix = "\n![图片](<"
        let suffix = ">)\n"
        while content.hasSuffix(suffix), let start = content.range(of: prefix, options: .backwards) {
            let address = content[start.upperBound...].dropLast(suffix.count)
            guard !address.contains(where: { $0.isWhitespace || $0 == ">" }),
                  let url = URL(string: String(address)), url.scheme == "https", url.host() != nil,
                  url.absoluteString == address else { break }
            images.append(url)
            content.removeSubrange(start.lowerBound...)
        }
        return images.reversed()
    }

    /// Decode only the leading reference written by replyReference for this thread.
    public mutating func removeReplyReference(postID: Int) -> (name: String, floor: Int, quote: String?)? {
        guard let reference = content.prefixMatch(of: #/^@([^\r\n]+?) \[#([0-9]+)\]\([^)]+\) /#),
              let floor = Int(reference.2) else { return nil }
        let name = String(reference.1)
        guard reference.0 == Self.replyReference(postID: postID, floor: floor, name: name) else { return nil }
        let body = content[reference.range.upperBound...]
        if let block = body.prefixMatch(of: #/^\n\n((?:> [^\n]*\n)+)\n/#) {
            let lines = block.1.dropLast().split(separator: "\n", omittingEmptySubsequences: false)
            let quote = lines.map { $0.dropFirst(2) }.joined(separator: "\n")
            content = String(body[block.range.upperBound...])
            return (name, floor, quote)
        }
        content = String(body)
        return (name, floor, nil)
    }

    public func validation(for mode: EditorMode) -> String? {
        if mode.editsTitle && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写帖子标题。" }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写正文。" }
        if mode == .newPost && category.isEmpty { return "请选择版块。" }
        if mode.editsTitle && !(0...6).contains(rank) && rank != 255 { return "请选择有效的阅读限制。" }
        return nil
    }
    public func body(for mode: EditorMode) -> [String: Any] {
        var body: [String: Any] = ["mode": mode.rawValue, "content": content]
        switch mode {
        case .newPost: body["title"] = title; body["category"] = category; body["rank"] = rank
        case .reply(let id): body["postId"] = id
        case .editPost(let id, _): body["postId"] = id; body["title"] = title; body["rank"] = rank
        case .editComment(let id): body["commentId"] = id
        }
        return body
    }
    public static func key(ownerID: Int, mode: EditorMode) -> String { "editor-draft-\(ownerID)-\(mode.rawValue)-\(mode.targetID)" }
    public static func replyReference(postID: Int, floor: Int, name: String, quote: String? = nil) -> String {
        let url = PostAddress.floorURL(postID: postID, floor: floor)
        let reference = "@\(name) [#\(floor)](\(url.absoluteString)) "
        guard let quote else { return reference }
        return reference + "\n\n" + quote.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n") + "\n\n"
    }
}
