import XCTest

@MainActor
final class RapidPostReturnTests: XCTestCase {
    func testCanReturnFromAPostByTappingBackOrSwipingDown() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try fixture()
        app.launch()

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "周末的读书计划")).firstMatch
        let back = app.buttons["返回"]
        let body = app.staticTexts["这个周末下午两点读书。"]
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

    private func fixture() throws -> String {
        let timestamp = "2025-01-04T12:00:00.000Z"
        let author: [String: Any] = ["uid": 101, "name": "楼主"]
        let post: [String: Any] = ["id": 123, "title": "周末的读书计划", "author": "楼主", "authorID": 101,
            "avatar": "", "category": "日常", "categoryKey": "daily", "views": 100, "replies": 0,
            "activityDate": timestamp, "pinned": false]
        let opening: [String: Any] = ["commentId": 501, "floorIndex": 0, "poster": author,
            "time": ["createdDate": timestamp], "markdown": "这个周末下午两点读书。", "likeCount": 0,
            "upvoteCount": 0, "blocked": false]
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [post], "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "https://www.nodeseek.com/post-123-1": ["postId": 123, "title": "周末的读书计划", "categoryWord": "日常",
                "views": "100", "postPage": 1, "postPageCount": 1, "collectionCount": 0, "op": author,
                "comments": [opening]]
        ]
        let fixture: [String: Any] = [
            "authentication": ["ready": true],
            "responses": try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
    }
}
