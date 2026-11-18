import XCTest

@MainActor
final class OfflineNavigationTests: XCTestCase {
    private func launchOffline() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-offline"]
        app.launch()
        return app
    }

    func testOfflineFeedCanRetryAndSelectACategory() {
        let app = launchOffline()
        let failure = ForumFixture.element("load-failure", in: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["网络未连接"].exists)
        XCTAssertTrue(app.staticTexts["请检查网络设置后重试。"].exists)
        assertNoSystemErrorText(in: app)
        #if !targetEnvironment(macCatalyst)
        XCTAssertTrue(app.buttons["打开设置"].exists)
        #endif

        // Retrying while still offline brings the same explanation back, not an empty page.
        let retry = app.buttons["重试"]
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(app.staticTexts["网络未连接"].waitForExistence(timeout: 10))
        assertNoSystemErrorText(in: app)

        let category = app.buttons["选择版块，当前全部"]
        XCTAssertTrue(category.waitForExistence(timeout: 10))
        category.tap()

        let daily = app.buttons["日常"]
        XCTAssertTrue(daily.waitForExistence(timeout: 5))
        daily.tap()
        XCTAssertTrue(app.buttons["选择版块，当前日常"].waitForExistence(timeout: 5))
    }

    func testOfflineTabsOfferRetryAndAccountOpensCommunityTools() {
        let app = launchOffline()
        let notifications = ForumFixture.tab("通知", in: app)
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()

        XCTAssertTrue(app.staticTexts["网络未连接"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["重试"].isHittable)
        assertNoSystemErrorText(in: app)

        let account = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()

        XCTAssertTrue(app.staticTexts["网络未连接"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["重试"].exists)
        assertNoSystemErrorText(in: app)

        let tools = app.staticTexts["社区工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()

        XCTAssertTrue(ForumFixture.title("社区工具", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["查找用户"].exists)
    }

    /// The system's own error text, such as "NSURLErrorDomain 错误 -1009", must never reach the reader.
    private func assertNoSystemErrorText(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let raw = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ErrorDomain' OR label CONTAINS '未能完成操作'"))
        XCTAssertEqual(raw.count, 0, "Raw system error text is on screen", file: file, line: line)
    }
}
