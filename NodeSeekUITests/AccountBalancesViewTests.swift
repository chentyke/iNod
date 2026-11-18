import XCTest

@MainActor
final class AccountBalancesViewTests: XCTestCase {
    private let readableWidth = 760 * ForumFixture.pointScale
    private let gutter = 16 * ForumFixture.pointScale
    private let tolerance: CGFloat = 2

    override func setUp() {
        continueAfterFailure = false
    }

    func testBalancesCardDisplaysValuesAlignsTilesAndNavigatesAllFourEntries() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchAccount(coins: 630, stardust: 4)
        scrollBalancesCardIntoCenter(in: app)

        let chickenTile = ForumFixture.element("account-balance-chicken", in: app)
        let stardustTile = ForumFixture.element("account-balance-stardust", in: app)
        let attendanceRow = app.buttons["签到"].firstMatch
        let progressRow = app.buttons["等级与进度"].firstMatch

        XCTAssertTrue(chickenTile.waitForExistence(timeout: 5))
        XCTAssertTrue(stardustTile.exists)
        XCTAssertTrue(attendanceRow.exists)
        XCTAssertTrue(progressRow.exists)

        XCTAssertEqual(chickenTile.label, "鸡腿")
        XCTAssertEqual(chickenTile.value as? String, (630).formatted())
        XCTAssertEqual(stardustTile.label, "星尘")
        XCTAssertEqual(stardustTile.value as? String, (4).formatted())

        let progressValue = progressRow.value as? String ?? ""
        XCTAssertTrue(progressValue.contains("Lv 2"), "Expected Lv 2 in progress value, got: \(progressValue)")
        XCTAssertTrue(progressValue.contains("270"), "Expected remaining 270 in progress value, got: \(progressValue)")

        // Both tiles share equal width, sit side-by-side at the same Y, and have a 12pt gap.
        XCTAssertLessThanOrEqual(abs(chickenTile.frame.width - stardustTile.frame.width), tolerance)
        XCTAssertLessThanOrEqual(abs(chickenTile.frame.minY - stardustTile.frame.minY), tolerance)
        XCTAssertLessThanOrEqual(abs((stardustTile.frame.minX - chickenTile.frame.maxX) - 12 * ForumFixture.pointScale), tolerance)

        assertReadableColumn(in: app)
        attachScreenshot(of: app, named: "after-light")

        chickenTile.tap()
        XCTAssertTrue(ForumFixture.title("鸡腿明细", in: app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(ForumFixture.title("我的", in: app).waitForExistence(timeout: 5))

        XCTAssertTrue(stardustTile.waitForExistence(timeout: 5))
        stardustTile.tap()
        XCTAssertTrue(ForumFixture.title("星尘明细", in: app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(ForumFixture.title("我的", in: app).waitForExistence(timeout: 5))

        XCTAssertTrue(attendanceRow.waitForExistence(timeout: 5))
        attendanceRow.tap()
        XCTAssertTrue(ForumFixture.title("每日签到", in: app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(ForumFixture.title("我的", in: app).waitForExistence(timeout: 5))

        XCTAssertTrue(progressRow.waitForExistence(timeout: 5))
        progressRow.tap()
        XCTAssertTrue(ForumFixture.title("等级与进度", in: app).waitForExistence(timeout: 5))
        #endif
    }

    func testDarkModeAndMaxLevelRenderBalancesCard() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchAccount(coins: 3800, stardust: 155, dark: true)
        scrollBalancesCardIntoCenter(in: app)
        XCTAssertTrue(ForumFixture.element("account-balance-chicken", in: app).waitForExistence(timeout: 5))

        let progressRow = app.collectionViews.firstMatch.buttons["等级与进度"].firstMatch
        XCTAssertTrue(progressRow.waitForExistence(timeout: 5))
        let progressValue = progressRow.value as? String ?? ""
        XCTAssertTrue(progressValue.contains("Lv 6"), "Expected Lv 6 in progress value, got: \(progressValue)")
        XCTAssertTrue(progressValue.contains("最高等级"), "Expected max-level summary in progress value, got: \(progressValue)")
        attachScreenshot(of: app, named: "after-max-dark")
        #endif
    }

    func testAccessibilitySizeStacksTilesAndHandlesUnknownBalances() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchAccount(
            coins: nil,
            stardust: nil,
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityLarge"]
        )
        let chickenTile = ForumFixture.element("account-balance-chicken", in: app)
        for _ in 0..<4 where !chickenTile.isHittable { app.swipeUp() }
        XCTAssertTrue(chickenTile.waitForExistence(timeout: 5))

        let stardustTile = ForumFixture.element("account-balance-stardust", in: app)
        for _ in 0..<2 where !stardustTile.exists { app.swipeUp() }
        XCTAssertTrue(stardustTile.waitForExistence(timeout: 5))

        XCTAssertEqual(chickenTile.value as? String, "未知")
        XCTAssertEqual(stardustTile.value as? String, "未知")
        XCTAssertLessThanOrEqual(chickenTile.frame.maxY, stardustTile.frame.minY + tolerance, "Tiles stack vertically at accessibility sizes.")
        attachScreenshot(of: app, named: "after-accessibility")
        #endif
    }

    private func scrollBalancesCardIntoCenter(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["鸡腿与星尘"].firstMatch.waitForExistence(timeout: 5))
    }

    private func assertReadableColumn(in app: XCUIApplication, line: UInt = #line) {
        let list = app.collectionViews.firstMatch
        let card = list.cells.containing(.any, identifier: "account-balances-grid").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), line: line)
        let listFrame = list.frame
        let rowFrame = card.frame
        XCTAssertLessThanOrEqual(rowFrame.width, readableWidth + tolerance, "Balances card keeps to readable width.", line: line)
        let expectedSideGap = max(gutter, ((listFrame.width - readableWidth) / 2).rounded(.down))
        XCTAssertLessThanOrEqual(abs((rowFrame.minX - listFrame.minX) - expectedSideGap), tolerance, line: line)
        XCTAssertLessThanOrEqual(abs((listFrame.maxX - rowFrame.maxX) - expectedSideGap), tolerance, line: line)
    }

    private func launchAccount(
        coins: Int?,
        stardust: Int?,
        dark: Bool = false,
        extraArguments: [String] = []
    ) throws -> XCUIApplication {
        let app = XCUIApplication()
        var user: [String: Any] = [
            "id": 9_900_315,
            "name": "测试用户",
            "topicCount": 12,
            "commentCount": 86
        ]
        if let coins { user["coins"] = coins }
        if let stardust { user["stardust"] = stardust }

        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [], "pinnedPosts": [], "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/account/credit/page-1": [
                "items": [
                    [
                        "id": "credit-1",
                        "change": 5,
                        "balance": coins ?? 630,
                        "reason": "每日签到",
                        "createdAt": "2026-11-17T00:02:18.000Z"
                    ]
                ],
                "hasNext": false
            ],
            "/api/stardust/history?member_id=9900315": [
                "items": [],
                "hasNext": false
            ],
            "/api/attendance/board?page=1": [
                "gain": 5,
                "order": 4,
                "createdAt": "2026-11-17T00:02:18.000Z",
                "total": 286,
                "items": [
                    ["id": 9_900_315, "name": "测试用户", "gain": 5, "rank": 4]
                ],
                "hasNext": false
            ],
            "/api/progress/today": [
                "postBonusCount": 1,
                "maxPostBonusCount": 4,
                "commentBonusCount": 8,
                "maxCommentBonusCount": 20,
                "freeLikeUsed": 1,
                "maxFreeLike": 3
            ]
        ]
        let encodedResponses = try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": user],
            "responses": encodedResponses
        ]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] =
            String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchArguments += ["-appearance", dark ? "dark" : "light"] + extraArguments
        app.launch()

        let myTab = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(myTab.waitForExistence(timeout: 8))
        myTab.tap()
        return app
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
