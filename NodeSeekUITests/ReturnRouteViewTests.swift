import XCTest

/// The return route page, driven by sample data so it runs offline and never publishes a real address.
@MainActor
final class ReturnRouteViewTests: XCTestCase {
    private func open(_ tool: String, sample: String = "complete", pace: String = "0.05") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-offline", "-qualitySample", sample, "-qualityPace", pace]
        app.launch()
        let account = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        let tools = app.staticTexts["社区工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        let entry = app.staticTexts[tool]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(ForumFixture.title(tool, in: app).waitForExistence(timeout: 5))
        return app
    }

    /// Opens the return route test from the network check without running the check first.
    private func openReturnRoute(pace: String = "0.05") -> XCUIApplication {
        let app = open("网络检测", pace: pace)
        let entry = app.staticTexts["回程线路"]
        for _ in 0..<6 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(ForumFixture.title("回程线路", in: app).waitForExistence(timeout: 5))
        return app
    }

    func testReturnRouteAsksBeforePublishingAndKeepsPartialResults() {
        let app = openReturnRoute()
        let field = app.descendants(matching: .any).matching(identifier: "returnRoute.target").firstMatch
        let start = app.buttons["returnRoute.start"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled, "Nothing runs without a target")

        field.tap()
        field.typeText("192.168.1.1")
        XCTAssertTrue(app.staticTexts["returnRoute.problem"].waitForExistence(timeout: 2))
        XCTAssertFalse(start.isEnabled, "Private addresses never reach the public service")

        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 11) + "203.0.113.80")
        XCTAssertFalse(app.staticTexts["returnRoute.problem"].exists)
        start.tap()
        // Starting only asks; the address goes out after the reader agrees to publish it.
        let publish = app.buttons["公开并开始测试"]
        XCTAssertTrue(publish.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["三网回程"].exists)
        func row(_ carrier: String, _ text: String) -> XCUIElement {
            // Rows combine for VoiceOver, so each row's words are one label.
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", carrier, text)).firstMatch
        }
        XCTAssertFalse(row("电信", "目标已回应").exists)
        publish.tap()

        XCTAssertTrue(row("电信", "目标已回应").waitForExistence(timeout: 10))
        XCTAssertTrue(row("移动", "没有对应运营商的节点回应").exists, "A carrier without a probe says why while the others still show")

        row("联通", "跳").tap()
        XCTAssertTrue(ForumFixture.title("联通回程", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["沿途节点"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '无回应'")).firstMatch.exists)
    }

    func testReturnRouteCancels() {
        let app = openReturnRoute(pace: "3")
        let field = app.descendants(matching: .any).matching(identifier: "returnRoute.target").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2001:db8::80")
        app.buttons["returnRoute.start"].tap()
        let publish = app.buttons["公开并开始测试"]
        XCTAssertTrue(publish.waitForExistence(timeout: 3))
        publish.tap()

        let cancel = app.buttons["returnRoute.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(app.buttons["returnRoute.start"].waitForExistence(timeout: 5))
        for carrier in ["电信", "联通", "移动"] {
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS '已取消'", carrier)).firstMatch
            XCTAssertTrue(row.exists, carrier)
        }
    }
}
