import XCTest

#if !targetEnvironment(macCatalyst)
@MainActor
final class AttendanceViewTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testUncheckedAttendanceShowsActionsAndKeepsReadableColumn() throws {
        let app = try launchAttendance(checkedIn: false)
        XCTAssertTrue(ForumFixture.title("每日签到", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今日尚未签到"].waitForExistence(timeout: 5))

        let fixedButton = ForumFixture.element("attendance-fixed-button", in: app)
        let randomButton = ForumFixture.element("attendance-random-button", in: app)
        XCTAssertTrue(fixedButton.exists)
        XCTAssertTrue(randomButton.exists)
        XCTAssertTrue(fixedButton.isHittable)
        XCTAssertTrue(randomButton.isHittable)

        let list = app.collectionViews.firstMatch
        ForumFixture.assertReadableRow(list.cells.firstMatch, in: list)
        attachScreenshot(of: app, named: "attendance-unchecked-light")
    }

    func testCheckedInAttendanceShowsSummaryAndNavigatesToMemberProfile() throws {
        let app = try launchAttendance(checkedIn: true)
        XCTAssertTrue(ForumFixture.title("每日签到", in: app).waitForExistence(timeout: 5))

        let statusCard = ForumFixture.element("attendance-status-card", in: app)
        XCTAssertTrue(statusCard.waitForExistence(timeout: 5))
        XCTAssertTrue(statusCard.label.contains("今日已签到"))
        XCTAssertTrue(statusCard.label.contains("+5"))
        XCTAssertTrue(statusCard.label.contains("今日第 4 位"))

        let myRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "测试用户", "我")).firstMatch
        XCTAssertTrue(myRow.exists, "The signed-in user's row should carry the '我' indicator.")

        attachScreenshot(of: app, named: "attendance-checked-light")

        let leader = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "林风")).firstMatch
        XCTAssertTrue(leader.isHittable)
        leader.tap()
        XCTAssertTrue(ForumFixture.title("个人主页", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["林风"].waitForExistence(timeout: 5))
    }

    private func launchAttendance(checkedIn: Bool) throws -> XCUIApplication {
        let app = XCUIApplication()
        let items: [[String: Any]] = [
            ["id": 9_900_001, "name": "林风", "gain": 8, "rank": 1],
            ["id": 9_900_002, "name": "阿泽", "gain": 5, "rank": 2],
            ["id": 9_900_003, "name": "周舟", "gain": 6, "rank": 3],
            ["id": 9_900_315, "name": "测试用户", "gain": 5, "rank": 4],
            ["id": 9_900_005, "name": "云端漫步", "gain": 3, "rank": 5],
            ["id": 9_900_006, "name": "北辰", "gain": 5, "rank": 6],
            ["id": 9_900_007, "name": "南山", "gain": 7, "rank": 7],
            ["id": 9_900_008, "name": "青禾", "gain": 5, "rank": 8]
        ]
        let uncheckedItems: [[String: Any]] = [
            ["id": 9_900_001, "name": "林风", "gain": 8, "rank": 1],
            ["id": 9_900_002, "name": "阿泽", "gain": 5, "rank": 2],
            ["id": 9_900_003, "name": "周舟", "gain": 6, "rank": 3],
            ["id": 9_900_005, "name": "云端漫步", "gain": 3, "rank": 4],
            ["id": 9_900_006, "name": "北辰", "gain": 5, "rank": 5],
            ["id": 9_900_007, "name": "南山", "gain": 7, "rank": 6],
            ["id": 9_900_008, "name": "青禾", "gain": 5, "rank": 7]
        ]
        var board: [String: Any] = [
            "total": checkedIn ? 286 : 285,
            "items": checkedIn ? items : uncheckedItems,
            "hasNext": false
        ]
        if checkedIn {
            board["gain"] = 5
            board["order"] = 4
            board["createdAt"] = "2026-11-17T00:02:18.000Z"
        }
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [], "pinnedPosts": [], "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/attendance/board?page=1": board,
            "/api/account/getInfo/9900001?readme=1": [
                "id": 9_900_001,
                "name": "林风",
                "bio": "早起打卡第一人",
                "readme": "保持阅读与分享。",
                "coins": 680,
                "stardust": 12,
                "topics": 15,
                "replies": 108,
                "follows": 9,
                "fans": 24,
                "followed": false
            ]
        ]
        let encodedResponses = try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": 9_900_315, "name": "测试用户", "coins": 1280, "stardust": 30]],
            "responses": encodedResponses
        ]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] =
            String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchArguments += ["-appearance", "light"]
        app.launch()

        let myTab = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(myTab.waitForExistence(timeout: 8))
        myTab.tap()

        let attendance = app.buttons["签到"].firstMatch
        for _ in 0..<4 where !attendance.isHittable { app.swipeUp() }
        XCTAssertTrue(attendance.waitForExistence(timeout: 5))
        attendance.tap()
        return app
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
