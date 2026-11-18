import XCTest

@MainActor
final class RapidPostReturnTests: XCTestCase {
    func testCanReturnFromAPostByTappingBackOrSwipingDown() {
        continueAfterFailure = false
        let opening = "这个周末下午两点读书。"
        let app = ForumFixture.launch(openingMarkdown: opening)

        let card = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
        let back = app.buttons["返回"]
        let body = app.staticTexts[opening]
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        card.tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            XCTAssertTrue(card.isHittable, "The feed card stays reachable beside the open thread on iPad.")
            let more = app.buttons["更多"]
            XCTAssertTrue(more.waitForExistence(timeout: 5))
            more.tap()
            let close = app.buttons["关闭帖子"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
            XCTAssertTrue(ForumFixture.element("feed-detail-placeholder", in: app).waitForExistence(timeout: 5))
            card.tap()
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            return
        }
        XCTAssertTrue(back.wait(for: \.isHittable, toEqual: true, timeout: 5))
        back.tap()
        XCTAssertTrue(card.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertFalse(back.exists)

        card.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        start.press(forDuration: 0, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(card.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertFalse(back.exists)
    }
}
