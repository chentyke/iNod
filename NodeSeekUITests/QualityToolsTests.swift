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
        let app = open("网络检测", pace: "0.6")
        app.buttons["quality.start"].tap()
        // Wait until the address lookups start, so the speed result is in and the rest is not.
        XCTAssertTrue(app.staticTexts["正在查询地址"].waitForExistence(timeout: 20))
        app.buttons["quality.cancel"].tap()

        XCTAssertTrue(app.staticTexts["已取消"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cloudflare 香港"].exists, "The finished speed result stays after a cancel")
        let resume = app.buttons["quality.retry"]
        XCTAssertTrue(resume.exists)
        XCTAssertTrue(resume.label.hasPrefix("继续剩余"))

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

    func testDeviceBenchmarkRunsOffline() {
        let app = open("本机性能")
        app.buttons["benchmark.start"].tap()
        XCTAssertTrue(app.buttons["benchmark.restart"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["历史成绩"].exists || app.collectionViews.firstMatch.staticTexts["历史成绩"].exists)
    }
}
