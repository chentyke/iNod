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

    func testSelectCategoryFromFeed() {
        let app = launchOffline()
        let category = app.buttons["选择版块，当前全部"]
        XCTAssertTrue(category.waitForExistence(timeout: 10))
        category.tap()

        let daily = app.buttons["日常"]
        XCTAssertTrue(daily.waitForExistence(timeout: 5))
        daily.tap()
        XCTAssertTrue(app.buttons["选择版块，当前日常"].waitForExistence(timeout: 5))
    }

    func testNotificationsOfferRetryWhenOffline() {
        let app = launchOffline()
        let notifications = ForumFixture.tab("通知", in: app)
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()

        XCTAssertTrue(app.staticTexts["无法确认登录状态"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["重试"].isHittable)
    }

    func testOpenCommunityToolsFromAccount() {
        let app = launchOffline()
        let account = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()

        let tools = app.staticTexts["社区工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()

        XCTAssertTrue(ForumFixture.title("社区工具", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["查找用户"].exists)
    }
}
