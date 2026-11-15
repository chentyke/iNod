import XCTest

@MainActor
final class ThreadHistoryTests: XCTestCase {
    private let title = "周末的读书计划"
    private let openingText = "周六下午两点开始读书。"
    private let timestamp = "2025-01-04T12:00:00.000Z"

    func testScrollingPinnedPostKeepsContentBelowTopControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture()
        app.launch()

        let post = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "置顶", title)).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        post.tap()

        let back = app.buttons["返回"]
        let heading = app.staticTexts[title]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(back.exists)
        let barBottom = back.frame.maxY
        let startingTitleY = heading.frame.minY
        XCTAssertGreaterThanOrEqual(startingTitleY, barBottom)

        let scrollView = app.scrollViews.firstMatch
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)

        XCTAssertLessThan(heading.frame.minY, startingTitleY, "The title should move when the post scrolls.")
        XCTAssertEqual(back.frame.maxY, barBottom, accuracy: 1, "The top controls should stay in place.")
        XCTAssertGreaterThanOrEqual(scrollView.frame.minY, barBottom - 1,
                                    "The scrolling viewport must start below the top controls.")
    }

    func testReplyNotificationCanScrollBackToEarlierPagesAndPostBody() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture()
        app.launch()

        let notifications = app.tabBars.buttons["通知"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()

        let notice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        notice.tap()

        let scrollView = app.scrollViews.firstMatch
        let targetReply = app.staticTexts[replyText(22)]
        XCTAssertTrue(targetReply.waitForExistence(timeout: 5))
        XCTAssertTrue(targetReply.isHittable, "The notification should open at the reply on page 3.")

        scrollView.swipeDown(velocity: .slow)
        let earlierReply = app.staticTexts[replyText(20)]
        XCTAssertTrue(reveal(earlierReply, in: scrollView), "Scrolling back should load a reply from page 2.")
        XCTAssertTrue(reveal(app.staticTexts[replyText(1)], in: scrollView), "Scrolling further should reach page 1.")
        XCTAssertTrue(reveal(app.staticTexts[openingText], in: scrollView), "Page 1 should show the post body.")
    }

    private func reveal(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return true }
            scrollView.swipeDown(velocity: .slow)
        }
        return element.exists && element.isHittable
    }

    private func replyText(_ floor: Int) -> String { "第 \(floor) 楼的回复" }

    private func websiteFixture() throws -> String {
        let pinnedPost: [String: Any] = ["id": 123, "title": title, "author": "楼主", "authorID": 101,
            "avatar": "", "category": "日常", "categoryKey": "daily", "views": 100, "replies": 30,
            "activityDate": timestamp, "pinned": true]
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [], "pinnedPosts": [pinnedPost], "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/notification/unread-count": ["unreadCount": ["all": 0]],
            "/api/notification/at-me/list": ["items": [], "hasNext": false],
            "/api/notification/reply-to-me/list": [
                "items": [["id": 1, "viewed": true, "postID": 123, "title": title, "floor": 22,
                           "authorID": 102, "author": "读者", "createdAt": timestamp]],
                "hasNext": false
            ],
            "https://www.nodeseek.com/post-123-1": threadPage(1, floors: 0...10),
            "https://www.nodeseek.com/post-123-2": threadPage(2, floors: 11...20),
            "https://www.nodeseek.com/post-123-3": threadPage(3, floors: 21...30)
        ]
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": 101, "name": "楼主"]],
            "responses": try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
    }

    private func threadPage(_ page: Int, floors: ClosedRange<Int>) -> [String: Any] {
        let author: [String: Any] = ["uid": 101, "name": "楼主"]
        let reader: [String: Any] = ["uid": 102, "name": "读者"]
        let comments: [[String: Any]] = floors.map { floor in
            ["commentId": 500 + floor, "floorIndex": floor, "poster": floor == 0 ? author : reader,
             "time": ["createdDate": timestamp], "markdown": floor == 0 ? openingText : replyText(floor),
             "likeCount": 0, "upvoteCount": 0, "blocked": false]
        }
        return ["postId": 123, "title": title, "categoryWord": "日常", "views": "100",
                "postPage": page, "postPageCount": 3, "collectionCount": 0, "op": author, "comments": comments]
    }
}
