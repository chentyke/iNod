import Foundation
import NodeSeekCore
import Testing

struct ForumSignatureTests {
    private let postURL = URL(string: "https://www.nodeseek.com/post-123-1")!

    @Test func keepsLinkTargetsAndDecodesHTML() {
        let signature = ForumSignature.attributed("""
        <p>📖 <a href="/space/101"><strong>读书会主页</strong></a> | <a href="https://example.com/?q=books&amp;page=2">书单 &amp; 笔记</a></p>
        <p>第一行<br>
        第二行</p>
        """, baseURL: postURL)

        #expect(String(signature.characters) == "📖 读书会主页 | 书单 & 笔记\n第一行\n第二行")
        #expect(signature.runs.compactMap(\.link?.absoluteString) == [
            "https://www.nodeseek.com/space/101", "https://example.com/?q=books&page=2"
        ])
        #expect(signature.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test func ignoresInvisibleContentAndUnsafeLinks() {
        let invisible = ForumSignature.attributed("<p>&nbsp;<br></p><script>hidden</script>", baseURL: postURL)
        #expect(invisible.characters.isEmpty)

        let signature = ForumSignature.attributed(#"<a href="javascript:alert(1)">签名</a>"#, baseURL: postURL)
        #expect(String(signature.characters) == "签名")
        #expect(signature.runs.allSatisfy { $0.link == nil })
    }
}
