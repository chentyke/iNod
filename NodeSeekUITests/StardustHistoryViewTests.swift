import XCTest

@MainActor
final class StardustHistoryViewTests: XCTestCase {
    private let readableWidth = 760 * ForumFixture.pointScale
    private let gutter = 16 * ForumFixture.pointScale
    private let tolerance: CGFloat = 2

    override func setUp() {
        continueAfterFailure = false
    }

    func testStardustHistoryDisplaysBalanceRecordsAndNavigates() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchStardustHistory()
        XCTAssertTrue(ForumFixture.title("星尘明细", in: app).waitForExistence(timeout: 5))

        let balanceSummary = ForumFixture.element("stardust-balance-summary", in: app)
        XCTAssertTrue(balanceSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(balanceSummary.label.contains("当前星尘"))
        XCTAssertTrue(balanceSummary.label.contains("155"))

        let transferButton = ForumFixture.element("stardust-transfer-button", in: app)
        XCTAssertTrue(transferButton.exists)
        XCTAssertTrue(transferButton.isHittable)

        let peerButton = ForumFixture.element("stardust-peer-508", in: app)
        XCTAssertTrue(peerButton.waitForExistence(timeout: 5))
        XCTAssertTrue(peerButton.label.contains("9900001"), "UID should not contain thousand separators.")
        XCTAssertFalse(peerButton.label.contains("9,900,001"))

        assertReadableColumn(in: app)
        attachScreenshot(of: app, named: "stardust-after-light")

        transferButton.tap()
        XCTAssertTrue(ForumFixture.title("星尘转账", in: app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(ForumFixture.title("星尘明细", in: app).waitForExistence(timeout: 5))

        XCTAssertTrue(peerButton.waitForExistence(timeout: 5))
        peerButton.tap()
        XCTAssertTrue(ForumFixture.title("个人主页", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["林风"].waitForExistence(timeout: 5))
        #endif
    }

    func testFilteringRecordsDisplaysActiveChipsAndClearsFilter() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchStardustHistory()
        XCTAssertTrue(app.staticTexts["购买邀请码"].waitForExistence(timeout: 5))

        let filterButton = ForumFixture.element("stardust-filter-button", in: app)
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.tap()
        XCTAssertTrue(ForumFixture.title("筛选记录", in: app).waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "stardust-after-filter-sheet")

        let transferType = ForumFixture.element("stardust-filter-type-transfer", in: app)
        XCTAssertTrue(transferType.waitForExistence(timeout: 5))
        transferType.tap()

        let applyButton = ForumFixture.element("stardust-filter-apply", in: app)
        XCTAssertTrue(applyButton.isEnabled)
        applyButton.tap()

        let activeFilters = ForumFixture.element("stardust-active-filters", in: app)
        XCTAssertTrue(activeFilters.waitForExistence(timeout: 5))
        XCTAssertTrue(ForumFixture.element("stardust-chip-type:transfer", in: app).exists)
        XCTAssertTrue(app.staticTexts["+25"].exists)
        XCTAssertFalse(app.staticTexts["购买邀请码"].exists)
        attachScreenshot(of: app, named: "stardust-after-filtered-light")

        let clearButton = ForumFixture.element("stardust-clear-filters", in: app)
        XCTAssertTrue(clearButton.isHittable)
        clearButton.tap()

        XCTAssertTrue(app.staticTexts["购买邀请码"].waitForExistence(timeout: 5))
        XCTAssertFalse(activeFilters.exists)
        #endif
    }

    func testDarkModeRendersStardustHistory() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchStardustHistory(dark: true)
        XCTAssertTrue(ForumFixture.element("stardust-balance-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["+25"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "stardust-after-dark")
        #endif
    }

    private func assertReadableColumn(in app: XCUIApplication, line: UInt = #line) {
        let list = app.collectionViews.containing(.any, identifier: "stardust-balance-card").firstMatch
        let card = list.cells.containing(.any, identifier: "stardust-balance-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), line: line)
        let listFrame = list.frame
        let rowFrame = card.frame
        XCTAssertLessThanOrEqual(rowFrame.width, readableWidth + tolerance, "Stardust card keeps to readable width.", line: line)
        let expectedSideGap = max(gutter, ((listFrame.width - readableWidth) / 2).rounded(.down))
        XCTAssertLessThanOrEqual(abs((rowFrame.minX - listFrame.minX) - expectedSideGap), tolerance, line: line)
        XCTAssertLessThanOrEqual(abs((listFrame.maxX - rowFrame.maxX) - expectedSideGap), tolerance, line: line)
    }

    private func launchStardustHistory(dark: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        let records: [[String: Any]] = [
            ["id": 508, "diff": 25, "result": 155, "type": "transfer", "created_at": "2026-11-17T09:30:00.000Z", "peer_id": 9_900_001, "ref_id": 100],
            ["id": 507, "diff": 1, "result": 130, "type": "upvote", "created_at": "2026-11-17T06:15:00.000Z", "peer_id": 9_900_002],
            ["id": 506, "diff": -100, "result": 129, "type": "buyCode", "created_at": "2026-11-16T14:20:00.000Z"],
            ["id": 505, "diff": -20, "result": 229, "type": "transfer", "created_at": "2026-11-15T19:45:00.000Z", "peer_id": 9_900_003, "ref_id": 208],
            ["id": 504, "diff": 50, "result": 249, "type": "system", "created_at": "2026-11-14T08:00:00.000Z"],
            ["id": 503, "diff": -10, "result": 199, "type": "admin", "created_at": "2026-11-12T11:10:00.000Z"]
        ]
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [], "pinnedPosts": [], "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/stardust/list?member_id=9900315&count=10": [
                "records": records,
                "exist_more": false,
                "cursor": 503
            ],
            "/api/stardust/list?member_id=9900315&count=10&type=transfer": [
                "records": [records[0], records[3]],
                "exist_more": false,
                "cursor": 505
            ],
            "/api/account/getInfo/9900001?readme=1": [
                "id": 9_900_001,
                "name": "林风",
                "bio": "早起打卡第一人",
                "readme": "保持阅读与分享。",
                "coins": 680,
                "stardust": 42,
                "topics": 15,
                "replies": 108,
                "follows": 9,
                "fans": 24,
                "followed": false
            ]
        ]
        let encodedResponses = try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": 9_900_315, "name": "测试用户", "coins": 1280, "stardust": 155]],
            "responses": encodedResponses
        ]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] =
            String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchArguments += ["-appearance", dark ? "dark" : "light"]
        app.launch()

        let myTab = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(myTab.waitForExistence(timeout: 8))
        myTab.tap()

        let stardust = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "星尘")).firstMatch
        for _ in 0..<4 where !stardust.isHittable { app.swipeUp() }
        XCTAssertTrue(stardust.waitForExistence(timeout: 5))
        stardust.tap()
        return app
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
