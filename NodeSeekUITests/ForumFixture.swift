import XCTest

/// A signed-out forum with one feed page and one thread, served offline through `NODESEEK_UI_TEST_WEBSITE`.
enum ForumFixture {
    static let threadTitle = "周末的读书计划"
    static let announcementTitle = "本月读书会公告"
    private static let timestamp = "2025-01-04T12:00:00.000Z"

    /// Launches the app on the fixture's feed.
    @MainActor static func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try? json()
        app.launch()
        return app
    }

    /// Launches the app and opens the fixture's thread from the feed.
    @MainActor static func launchThread() -> XCUIApplication {
        let app = launch()
        let post = postCard(threadTitle, in: app)
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        post.tap()
        XCTAssertTrue(app.otherElements["comment-2"].waitForExistence(timeout: 8))
        return app
    }

    /// A tab in the root tab bar. iPhone shows it in a tab bar; iPad and Mac show the tabs as plain buttons at the top.
    @MainActor static func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    @MainActor static func postCard(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private static func json() throws -> String {
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
        let posts = [post(123, threadTitle)] + (1...8).map { post(200 + $0, $0 == 1 ? announcementTitle : "读书笔记第 \($0) 篇") }
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": posts, "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "https://www.nodeseek.com/post-123-1": ["postId": 123, "title": threadTitle, "categoryWord": "日常",
                "views": "100", "postPage": 1, "postPageCount": 1, "collectionCount": 0, "op": author,
                "comments": replies],
            "https://www.nodeseek.com/post-201-1": ["postId": 201, "title": announcementTitle, "categoryWord": "日常",
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
