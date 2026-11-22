import NodeSeekCore
import SwiftUI

struct CommentSignatureView: View {
    let html: String
    let floor: Int
    @Environment(\.forumDocumentURL) private var documentURL

    var body: some View {
        let signature = styledSignature
        if !signature.characters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Color.seekHairline).frame(height: 0.5)
                    .accessibilityHidden(true)
                TextWithTrailingLabel(text: Text(signature).font(.subheadline), label: nil,
                                      hasLinks: signature.runs.contains { $0.link != nil })
                    .accessibilityIdentifier("comment-signature-\(floor)")
            }
        }
    }

    private var styledSignature: AttributedString {
        var signature = ForumSignature.attributed(html, baseURL: documentURL)
        let linkRanges = signature.runs.filter { $0.link != nil }.map(\.range)
        signature.foregroundColor = Color.secondary
        for range in linkRanges {
            signature[range].foregroundColor = Color.seekGreen
        }
        return signature
    }
}
