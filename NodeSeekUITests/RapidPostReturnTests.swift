import XCTest

@MainActor
final class RapidPostReturnTests: XCTestCase {
    func testCanReturnFromAPostByTappingBackOrSwipingDown() {
        continueAfterFailure = false
        let opening = "周六下午两点开始读书。"
        let app = ForumFixture.launch(openingMarkdown: opening)

        let card = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
        let back = app.buttons["返回"]
        let body = app.staticTexts[opening]
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        let isSplit = ForumFixture.element("feed-detail-placeholder", in: app).exists
        let community = ForumFixture.tab("社区", in: app)
        let account = ForumFixture.tab("我的", in: app)
        let hasSideTabs = UIDevice.current.userInterfaceIdiom == .phone && community.frame.maxY <= account.frame.minY
        card.tap()
        if isSplit {
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            XCTAssertTrue(card.isHittable, "The feed card stays reachable beside the open thread.")
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
        if hasSideTabs {
            XCTAssertGreaterThan(back.frame.minX, app.buttons["更多"].frame.maxX)
            XCTAssertEqual(back.frame.midX, community.frame.midX, accuracy: 3)
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.name = "Folded thread"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        back.tap()
        XCTAssertTrue(card.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertFalse(back.exists)
        XCTAssertFalse(body.exists)
        if hasSideTabs {
            XCTAssertFalse(card.isSelected)
            return
        }

        card.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        start.press(forDuration: 0, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(card.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertFalse(back.exists)
    }
}
