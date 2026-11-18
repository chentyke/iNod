import XCTest

/// The network check and device benchmark, driven by sample data so they run offline and fast.
@MainActor
final class QualityToolsTests: XCTestCase {
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

    func testNetworkCheckRunsToAReport() {
        let app = open("网络检测")
        let start = app.buttons["quality.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.buttons["quality.restart"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["203.0.113.24"].exists)
        XCTAssertFalse(app.buttons["quality.retry"].exists, "A complete run has nothing to retry")
        XCTAssertTrue(app.buttons["quality.share"].exists)
    }

    func testCancelKeepsFinishedResultsAndResumes() {
        let app = open("网络检测", pace: "0.9")
        app.buttons["quality.start"].tap()
        // Wait until the address lookups start, so the speed result is in and the rest is not.
        XCTAssertTrue(app.staticTexts["正在查询地址"].waitForExistence(timeout: 20))
        app.buttons["quality.cancel"].tap()

        let resume = app.buttons["quality.retry"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        XCTAssertTrue(resume.label.hasPrefix("继续剩余"))
        let download = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", "下载", "486 Mbps")).firstMatch
        XCTAssertTrue(download.exists, "The finished download stays in the summary after cancellation")

        resume.tap()
        XCTAssertTrue(app.buttons["quality.cancel"].waitForExistence(timeout: 5))
    }

    func testPartialFailureOffersRetry() {
        let app = open("网络检测", sample: "partialFailure")
        app.buttons["quality.start"].tap()
        let retry = app.buttons["quality.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        XCTAssertEqual(retry.label, "重试 5 项")
        // The timed-out upload is named near the top, where its row says why. Rows combine for VoiceOver,
        // so the reason is part of the row's label.
        let upload = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '上传' AND label CONTAINS '超时'")).firstMatch
        XCTAssertTrue(upload.exists)
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

    func testDeviceBenchmarkRunsOffline() {
        let app = open("本机性能")
        app.buttons["benchmark.start"].tap()
        XCTAssertTrue(app.buttons["benchmark.restart"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["历史成绩"].exists || app.collectionViews.firstMatch.staticTexts["历史成绩"].exists)
    }
}
