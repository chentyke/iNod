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
