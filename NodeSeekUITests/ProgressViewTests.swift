import XCTest

@MainActor
final class ProgressViewTests: XCTestCase {
    private let readableWidth = 760 * ForumFixture.pointScale
    private let gutter = 16 * ForumFixture.pointScale
    private let tolerance: CGFloat = 2

    override func setUp() {
        continueAfterFailure = false
    }

    func testUpgradingProgressShowsLevelQuotasAndKeepsReadableColumn() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchProgress(
            coins: 1280,
            postBonusCount: 1,
            maxPostBonusCount: 4,
            commentBonusCount: 8,
            maxCommentBonusCount: 20,
            freeLikeUsed: 1,
            maxFreeLike: 3
        )
        XCTAssertTrue(ForumFixture.title("等级与进度", in: app).waitForExistence(timeout: 5))

        let levelCard = ForumFixture.element("progress-level-card", in: app)
        XCTAssertTrue(levelCard.waitForExistence(timeout: 5))
        XCTAssertTrue(levelCard.label.contains("社区等级"))
        XCTAssertTrue(levelCard.label.contains("Lv 3"))
        XCTAssertTrue(levelCard.label.contains("距离 Lv 4 还需 320 个鸡腿"))
        XCTAssertTrue(levelCard.label.contains("当前 1,280 鸡腿"))
        XCTAssertTrue(levelCard.label.contains("Lv 4 门槛 1,600 鸡腿"))

        let postRow = ForumFixture.element("progress-row-post", in: app)
        let commentRow = ForumFixture.element("progress-row-comment", in: app)
        let freeLikeRow = ForumFixture.element("progress-row-freelike", in: app)
        XCTAssertTrue(postRow.exists)
        XCTAssertTrue(commentRow.exists)
        XCTAssertTrue(freeLikeRow.exists)
        XCTAssertTrue(postRow.label.contains("1 / 4"))
        XCTAssertTrue(postRow.label.contains("还可获得 3 次发帖奖励"))
        XCTAssertTrue(commentRow.label.contains("8 / 20"))
        XCTAssertTrue(commentRow.label.contains("还可获得 12 次回复奖励"))
        XCTAssertTrue(freeLikeRow.label.contains("1 / 3"))
        XCTAssertTrue(freeLikeRow.label.contains("还可免费投喂 2 次"))

        assertReadableColumn(in: app)
        attachScreenshot(of: app, named: "progress-upgrading-light")

        let currentTier = ForumFixture.element("progress-tier-3", in: app)
        let maxTier = ForumFixture.element("progress-tier-6", in: app)
        for _ in 0..<4 where !maxTier.isHittable { app.swipeUp() }
        XCTAssertTrue(currentTier.waitForExistence(timeout: 5))
        XCTAssertTrue(currentTier.label.contains("Lv 3"))
        XCTAssertTrue(currentTier.label.contains("当前"))
        XCTAssertTrue(currentTier.label.contains("900 鸡腿"))
        XCTAssertTrue(maxTier.exists)
        XCTAssertTrue(maxTier.label.contains("Lv 6"))
        XCTAssertTrue(maxTier.label.contains("3,600 鸡腿"))
        attachScreenshot(of: app, named: "progress-tiers-light")
        #endif
    }

    func testMaxLevelProgressShowsCompletedStatusAndNavigatesToRelatedPages() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchProgress(
            coins: 3800,
            postBonusCount: 4,
            maxPostBonusCount: 4,
            commentBonusCount: 20,
            maxCommentBonusCount: 20,
            freeLikeUsed: 3,
            maxFreeLike: 3
        )
        XCTAssertTrue(ForumFixture.title("等级与进度", in: app).waitForExistence(timeout: 5))

        let levelCard = ForumFixture.element("progress-level-card", in: app)
        XCTAssertTrue(levelCard.waitForExistence(timeout: 5))
        XCTAssertTrue(levelCard.label.contains("已达最高等级"))
        XCTAssertTrue(levelCard.label.contains("Lv 6"))
        XCTAssertTrue(levelCard.label.contains("当前 3,800 鸡腿"))
        XCTAssertTrue(levelCard.label.contains("满级门槛 3,600 鸡腿"))

        XCTAssertTrue(ForumFixture.element("progress-row-post", in: app).label.contains("今日发帖奖励已领满"))
        XCTAssertTrue(ForumFixture.element("progress-row-comment", in: app).label.contains("今日回复奖励已领满"))
        XCTAssertTrue(ForumFixture.element("progress-row-freelike", in: app).label.contains("今日免费投喂额度已用完"))

        attachScreenshot(of: app, named: "progress-max-light")

        let attendanceLink = app.buttons["每日签到"].firstMatch
        for _ in 0..<3 where !attendanceLink.isHittable { app.swipeUp() }
        XCTAssertTrue(attendanceLink.waitForExistence(timeout: 5))
        attendanceLink.tap()
        XCTAssertTrue(ForumFixture.title("每日签到", in: app).waitForExistence(timeout: 5))

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(ForumFixture.title("等级与进度", in: app).waitForExistence(timeout: 5))

        let ledgerLink = app.buttons["鸡腿明细"].firstMatch
        for _ in 0..<3 where !ledgerLink.isHittable { app.swipeUp() }
        XCTAssertTrue(ledgerLink.waitForExistence(timeout: 5))
        ledgerLink.tap()
        XCTAssertTrue(ForumFixture.title("鸡腿明细", in: app).waitForExistence(timeout: 5))
        #endif
    }

    func testDarkModeProgressRendersBothStates() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let upgrading = try launchProgress(
            coins: 1280,
            postBonusCount: 1,
            maxPostBonusCount: 4,
            commentBonusCount: 8,
            maxCommentBonusCount: 20,
            freeLikeUsed: 1,
            maxFreeLike: 3,
            dark: true
        )
        XCTAssertTrue(ForumFixture.element("progress-level-card", in: upgrading).waitForExistence(timeout: 5))
        attachScreenshot(of: upgrading, named: "progress-upgrading-dark")
        upgrading.terminate()

        let maxLevel = try launchProgress(
            coins: 3800,
            postBonusCount: 4,
            maxPostBonusCount: 4,
            commentBonusCount: 20,
            maxCommentBonusCount: 20,
            freeLikeUsed: 3,
            maxFreeLike: 3,
            dark: true
        )
        XCTAssertTrue(ForumFixture.element("progress-level-card", in: maxLevel).waitForExistence(timeout: 5))
        attachScreenshot(of: maxLevel, named: "progress-max-dark")
        #endif
    }

    func testAccessibilityTextSizeStacksContentWithoutLosingSummary() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchProgress(
            coins: 1280,
            postBonusCount: 0,
            maxPostBonusCount: 4,
            commentBonusCount: 5,
            maxCommentBonusCount: 20,
            freeLikeUsed: 0,
            maxFreeLike: 0,
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityLarge"]
        )
        let levelCard = ForumFixture.element("progress-level-card", in: app)
        XCTAssertTrue(levelCard.waitForExistence(timeout: 5))
        XCTAssertTrue(levelCard.label.contains("Lv 3"))
        XCTAssertTrue(levelCard.label.contains("当前 1,280 鸡腿"))

        let freeLikeRow = ForumFixture.element("progress-row-freelike", in: app)
        for _ in 0..<4 where !freeLikeRow.exists { app.swipeUp() }
        XCTAssertTrue(freeLikeRow.waitForExistence(timeout: 5))
        XCTAssertTrue(freeLikeRow.label.contains("当前暂无每日免费投喂额度"))
        #endif
    }

    private func assertReadableColumn(in app: XCUIApplication, line: UInt = #line) {
        let list = app.collectionViews.firstMatch
        let firstCell = list.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5), line: line)
        let listFrame = list.frame
        let rowFrame = firstCell.frame
        XCTAssertLessThanOrEqual(rowFrame.width, readableWidth + tolerance, "Progress card keeps to readable width.", line: line)
        let expectedSideGap = max(gutter, ((listFrame.width - readableWidth) / 2).rounded(.down))
        XCTAssertLessThanOrEqual(abs((rowFrame.minX - listFrame.minX) - expectedSideGap), tolerance, line: line)
        XCTAssertLessThanOrEqual(abs((listFrame.maxX - rowFrame.maxX) - expectedSideGap), tolerance, line: line)
    }

    private func launchProgress(
        coins: Int,
        postBonusCount: Int,
        maxPostBonusCount: Int,
        commentBonusCount: Int,
        maxCommentBonusCount: Int,
        freeLikeUsed: Int,
        maxFreeLike: Int,
        dark: Bool = false,
        extraArguments: [String] = []
    ) throws -> XCUIApplication {
        let app = XCUIApplication()
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [], "pinnedPosts": [], "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/progress/today": [
                "postBonusCount": postBonusCount,
                "maxPostBonusCount": maxPostBonusCount,
                "commentBonusCount": commentBonusCount,
                "maxCommentBonusCount": maxCommentBonusCount,
                "freeLikeUsed": freeLikeUsed,
                "maxFreeLike": maxFreeLike
            ],
            "/api/attendance/board?page=1": [
                "gain": 5,
                "order": 4,
                "createdAt": "2026-11-17T00:02:18.000Z",
                "total": 286,
                "items": [
                    ["id": 9_900_001, "name": "林风", "gain": 8, "rank": 1],
                    ["id": 9_900_315, "name": "测试用户", "gain": 5, "rank": 4]
                ],
                "hasNext": false
            ],
            "/api/account/credit/page-1": [
                "items": [
                    [
                        "id": "credit-1",
                        "change": 5,
                        "balance": coins,
                        "reason": "每日签到",
                        "createdAt": "2026-11-17T00:02:18.000Z"
                    ]
                ],
                "hasNext": false
            ]
        ]
        let encodedResponses = try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": 9_900_315, "name": "测试用户", "coins": coins, "stardust": 30]],
            "responses": encodedResponses
        ]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] =
            String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchArguments += ["-appearance", dark ? "dark" : "light"] + extraArguments
        app.launch()

        let myTab = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(myTab.waitForExistence(timeout: 8))
        myTab.tap()

        let progressRow = app.buttons["等级与进度"].firstMatch
        for _ in 0..<4 where !progressRow.isHittable { app.swipeUp() }
        XCTAssertTrue(progressRow.waitForExistence(timeout: 5))
        progressRow.tap()
        return app
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
