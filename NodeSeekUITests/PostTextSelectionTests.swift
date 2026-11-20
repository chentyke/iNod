import UIKit
import XCTest

#if !targetEnvironment(macCatalyst)
@MainActor
final class PostTextSelectionTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCanCopyMultipleParagraphsFromOpeningPost() {
        let app = ForumFixture.launch(opensThread: true, signedInAsAuthor: true,
                                      authorID: Int.random(in: 1_000_000...2_000_000), openingMarkdown: """
            Reading starts at **two**.

            Bring the [reading list](https://example.com/list).

            See you there.

            - 笔记本
            - 铅笔
            """)
        let card = ForumFixture.element("comment-0", in: app)
        let text = card.textViews["post-selectable-text"]
        let expected = "Reading starts at two.\nBring the reading list.\nSee you there."
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertEqual(text.value as? String, expected)
        assertCopyMenu(on: text, in: app)

        let origin = text.coordinate(withNormalizedOffset: .zero)
        let font = UIFont.preferredFont(forTextStyle: .body)
        let wordWidth = ("Reading" as NSString).size(withAttributes: [.font: font]).width
        let handle = origin.withOffset(CGVector(dx: wordWidth, dy: font.lineHeight + 5))
        let nextParagraph = origin.withOffset(CGVector(dx: wordWidth, dy: text.frame.height - 8))
        handle.press(forDuration: 0.1, thenDragTo: nextParagraph, withVelocity: .slow, thenHoldForDuration: 0.2)
        let afterDrag = XCTAttachment(screenshot: app.screenshot())
        afterDrag.name = "正文跨段选择"
        afterDrag.lifetime = .keepAlways
        add(afterDrag)
        let copy = copyAction(in: app)
        XCTAssertTrue(copy.wait(for: \.isHittable, toEqual: true, timeout: 5))
        copy.tap()

        app.buttons["写回复"].tap()
        let reply = ForumFixture.element("回复正文", in: app)
        XCTAssertTrue(reply.wait(for: \.isHittable, toEqual: true, timeout: 8))
        reply.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 1)
        let paste = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Paste", "粘贴", "貼上"])).firstMatch
        XCTAssertTrue(paste.wait(for: \.isHittable, toEqual: true, timeout: 8))
        paste.tap()
        let pasted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "Reading starts at two.\nBring"),
            object: reply
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pasted], timeout: 8), .completed, reply.value as? String ?? "")
    }

    func testReplyTextCanBeSelectedInItsCard() {
        let app = ForumFixture.launch(opensThread: true, firstReplyMarkdown: "下周一起读。\n\n记得带书。")
        let card = ForumFixture.element("comment-1", in: app)
        let text = card.textViews["post-selectable-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertEqual(text.value as? String, "下周一起读。\n记得带书。")
        assertCopyMenu(on: text, in: app)
    }

    func testTableKeepsTheTextOnEachSideSelectable() {
        let app = ForumFixture.launch(opensThread: true, openingMarkdown: """
            Before the table.

            | Day | Book |
            | --- | --- |
            | Monday | Poetry |

            After the table.
            """)
        let card = ForumFixture.element("comment-0", in: app)
        let before = ForumFixture.threadText("Before the table.", in: card)
        let after = ForumFixture.threadText("After the table.", in: card)
        XCTAssertTrue(before.waitForExistence(timeout: 10))
        XCTAssertTrue(after.exists)
        let table = card.descendants(matching: .any)["markdown-table"].firstMatch
        XCTAssertTrue(table.exists)
        XCTAssertTrue(table.staticTexts["Poetry"].exists)
        XCTAssertLessThan(before.frame.maxY, table.frame.minY)
        XCTAssertLessThan(table.frame.maxY, after.frame.minY)
    }

    func testTappingFloorLinkStillUsesThreadNavigation() {
        let app = ForumFixture.launch(opensThread: true, openingMarkdown: "See #7 for details.")
        let card = ForumFixture.element("comment-0", in: app)
        let text = card.textViews["post-selectable-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        text.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 42, dy: 10)).tap()
        XCTAssertTrue(app.alerts["操作未完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["没有找到这条回复。"].exists)
    }

    private func assertCopyMenu(on text: XCUIElement, in app: XCUIApplication, line: UInt = #line) {
        XCTAssertTrue(text.wait(for: \.isHittable, toEqual: true, timeout: 10), line: line)
        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        let word = text.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 26, dy: lineHeight / 2))
        let copy = copyAction(in: app)
        for _ in 0..<2 {
            word.press(forDuration: 1)
            if copy.waitForExistence(timeout: 5) {
                XCTAssertFalse(app.keyboards.firstMatch.exists, line: line)
                return
            }
        }
        XCTFail("Long-pressing the post text should show the system Copy menu.", line: line)
    }

    private func copyAction(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Copy", "拷贝", "复制", "複製"])).firstMatch
    }
}
#endif
