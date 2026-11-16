import XCTest

/// Checks the parts of docs/DESIGN.md that a running app can measure: corner controls sit as far from
/// the card's side as from its bottom (rule 6), and transient states close on an outside tap or a scroll
/// without swallowing taps inside them (rule 8).
@MainActor
final class DesignChecklistTests: XCTestCase {
    /// docs/DESIGN.md allows 2 points between gaps that should match.
    private let tolerance: CGFloat = 2
    private let title = "周末的读书计划"
    private let timestamp = "2025-01-04T12:00:00.000Z"

    override func setUp() {
        continueAfterFailure = false
    }

    func testReplyDockKeepsEvenGapsToTheCardEdges() throws {
        let app = launchThread()
        let card = app.otherElements["comment-2"]
        let dock = foldedDock(in: card)
        XCTAssertTrue(dock.waitForExistence(timeout: 5))

        assertEven(side: card.frame.maxX - dock.frame.maxX, bottom: card.frame.maxY - dock.frame.maxY, "Folded dock")

        dock.tap()
        let more = card.buttons["更多回复操作"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        // Let the opening spring settle before measuring.
        XCTAssertTrue(more.wait(for: \.isHittable, toEqual: true, timeout: 3))
        Thread.sleep(forTimeInterval: 0.6)
        assertEven(side: card.frame.maxX - more.frame.maxX, bottom: card.frame.maxY - more.frame.maxY, "Opened dock")
        XCTAssertLessThanOrEqual(more.frame.maxY, card.frame.maxY, "The opened dock stays inside its card.")
    }

    func testOpenedDockFoldsOnOutsideTapScrollAndAnotherDock() throws {
        let app = launchThread()
        let first = app.otherElements["comment-2"]
        let second = app.otherElements["comment-3"]
        XCTAssertTrue(foldedDock(in: first).waitForExistence(timeout: 5))

        // A tap in the gap between cards folds it. Tap above the card: below it may sit under the reply bar.
        foldedDock(in: first).tap()
        XCTAssertTrue(first.buttons["回复"].waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: first.frame.midX, dy: first.frame.minY - 5)).tap()
        XCTAssertTrue(foldedDock(in: first).waitForExistence(timeout: 3), "A tap outside should fold the dock.")

        // Opening another dock folds the first, so only one is open.
        foldedDock(in: first).tap()
        XCTAssertTrue(first.buttons["回复"].waitForExistence(timeout: 3))
        foldedDock(in: second).tap()
        XCTAssertTrue(second.buttons["回复"].waitForExistence(timeout: 3))
        XCTAssertTrue(foldedDock(in: first).waitForExistence(timeout: 3), "Only one dock should be open at a time.")

        // A scroll folds it too.
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        XCTAssertTrue(app.buttons["回复"].waitForNonExistence(timeout: 3), "Scrolling should fold the dock.")
    }

    func testFeedSearchFoldsOnScrollAndStaysFoldedAfterAPost() throws {
        let app = launchThread(opensPost: false)
        let open = app.buttons["搜索帖子"]
        let close = app.buttons["关闭搜索"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))

        open.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        // Drag in the top half: the software keyboard covers the bottom, and dragging on it scrolls nothing.
        drag(app, from: 0.5, to: 0.2)
        XCTAssertTrue(open.waitForExistence(timeout: 3), "Scrolling should fold an empty search.")

        drag(app, from: 0.3, to: 0.8)
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "本月读书会公告")).firstMatch
        XCTAssertTrue(card.wait(for: \.isHittable, toEqual: true, timeout: 3))
        Thread.sleep(forTimeInterval: 1) // let the list stop, so the next tap is a tap
        open.tap()
        XCTAssertTrue(close.wait(for: \.isHittable, toEqual: true, timeout: 3))

        // Leaving for a post and coming back keeps the empty search folded and the keyboard down.
        card.tap()
        let back = app.buttons["返回"]
        XCTAssertTrue(back.wait(for: \.isHittable, toEqual: true, timeout: 5))
        back.tap()
        XCTAssertTrue(open.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertEqual(app.keyboards.count, 0, "Returning to the feed must not bring the keyboard back.")
    }

    // MARK: - Helpers

    /// Scrolls whatever list is on screen by dragging between two heights given as fractions of the screen.
    private func drag(_ app: XCUIApplication, from start: CGFloat, to end: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
            .press(forDuration: 0, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end)))
    }

    private func foldedDock(in card: XCUIElement) -> XCUIElement {
        card.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "回复操作")).firstMatch
    }

    private func assertEven(side: CGFloat, bottom: CGFloat, _ name: String, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(side - bottom), tolerance,
                                 "\(name): side gap \(side) and bottom gap \(bottom) should match.", line: line)
    }

    private func launchThread(opensPost: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try? fixture()
        app.launch()
        guard opensPost else { return app }
        let post = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        post.tap()
        XCTAssertTrue(app.otherElements["comment-2"].waitForExistence(timeout: 8))
        return app
    }

    private func fixture() throws -> String {
        let author: [String: Any] = ["uid": 101, "name": "楼主"]
        let reader: [String: Any] = ["uid": 102, "name": "读者"]
        func post(_ id: Int, _ title: String) -> [String: Any] {
            ["id": id, "title": title, "author": "楼主", "authorID": 101, "avatar": "", "category": "日常",
             "categoryKey": "daily", "views": 100, "replies": 6, "activityDate": timestamp, "pinned": false]
        }
        let replies: [[String: Any]] = (0...6).map { floor in
            ["commentId": 500 + floor, "floorIndex": floor, "poster": floor == 0 ? author : reader,
             "time": ["createdDate": timestamp], "markdown": floor == 0 ? "周六下午两点开始读书。" : "第 \(floor) 楼：一起读。",
             "likeCount": 0, "upvoteCount": 0, "blocked": false]
        }
        let posts = [post(123, title)] + (1...8).map { post(200 + $0, $0 == 1 ? "本月读书会公告" : "读书笔记第 \($0) 篇") }
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": posts, "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "https://www.nodeseek.com/post-123-1": ["postId": 123, "title": title, "categoryWord": "日常",
                "views": "100", "postPage": 1, "postPageCount": 1, "collectionCount": 0, "op": author,
                "comments": replies],
            "https://www.nodeseek.com/post-201-1": ["postId": 201, "title": "本月读书会公告", "categoryWord": "日常",
                "views": "100", "postPage": 1, "postPageCount": 1, "collectionCount": 0, "op": author,
                "comments": Array(replies.prefix(1))]
        ]
        let fixture: [String: Any] = [
            "authentication": ["ready": true],
            "responses": try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
    }
}
