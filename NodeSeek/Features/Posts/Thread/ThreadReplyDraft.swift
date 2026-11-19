import Foundation
import NodeSeekCore

struct ThreadReplyTarget: Equatable {
    let name: String
    let floor: Int

    let quote: String?
    let excerpt: String?

    init(name: String, floor: Int, quote: String? = nil) {
        self.name = name
        self.floor = floor
        self.quote = quote
        excerpt = quote.map { source in
            let sample = String(source.prefix(512))
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let rendered = try? AttributedString(markdown: sample, options: options)
            let text = rendered.map { String($0.characters) } ?? sample
            return text.replacingOccurrences(of: "\u{fffc}", with: "图片")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    func reference(postID: Int) -> String {
        EditorDraft.replyReference(postID: postID, floor: floor, name: name, quote: quote)
    }
}

enum ThreadReplyRequest: Equatable {
    case write
    case respond(ThreadReplyTarget)
}

struct ThreadReplyDraft {
    var text = ""
    var target: ThreadReplyTarget?
    var images: [URL] = []

    init() {}

    init(stored: EditorDraft?, postID: Int) {
        var draft = stored ?? EditorDraft()
        images = draft.removeTrailingHostedImages()
        if let reference = draft.removeReplyReference(postID: postID) {
            target = ThreadReplyTarget(name: reference.name, floor: reference.floor, quote: reference.quote)
        }
        text = draft.content
    }

    func editorDraft(postID: Int) -> EditorDraft {
        var draft = EditorDraft(content: (target?.reference(postID: postID) ?? "") + text)
        for url in images { draft.appendHostedImage(url) }
        return draft
    }
}
