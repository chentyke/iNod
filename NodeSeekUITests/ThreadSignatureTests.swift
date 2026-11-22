import XCTest

@MainActor
final class ThreadSignatureTests: XCTestCase {
    func testOpeningPostAndReplyShowTheirSignatures() {
        continueAfterFailure = false
        let app = ForumFixture.launch(dark: true, opensThread: true, signatures: [
            0: #"<p>📖 <a href="/space/101">读书会主页</a> | <a href="https://example.com/books">本月书单</a></p>"#,
            1: "<p><strong>正在读《小王子》</strong></p>",
            2: "<p> <br> </p>"
        ])
        let opening = ForumFixture.element("comment-0", in: app)
        let reply = ForumFixture.element("comment-1", in: app)
        XCTAssertTrue(reply.waitForExistence(timeout: 8))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Thread signatures"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let openingSignature = ForumFixture.element("comment-signature-0", in: app)
        let replySignature = ForumFixture.element("comment-signature-1", in: app)
        XCTAssertTrue(openingSignature.exists)
        XCTAssertTrue(replySignature.exists)
        XCTAssertEqual(openingSignature.label, "📖 读书会主页 | 本月书单")
        XCTAssertEqual(replySignature.label, "正在读《小王子》")
        XCTAssertTrue(ForumFixture.element("comment-2", in: app).exists)
        XCTAssertFalse(ForumFixture.element("comment-signature-2", in: app).exists)
        XCTAssertLessThan(ForumFixture.threadText("周六下午两点开始读书。", in: opening).frame.maxY,
                          openingSignature.frame.minY)
        XCTAssertLessThan(ForumFixture.threadText("第 1 楼：一起读。", in: reply).frame.maxY,
                          replySignature.frame.minY)

        openingSignature.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["周末读书会发起人"].waitForExistence(timeout: 5))
    }
}
