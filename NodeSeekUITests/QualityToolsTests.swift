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

    private func openCarrierSpeed(sample: String = "complete", pace: String = "0.05") -> XCUIApplication {
        let app = open("网络检测", sample: sample, pace: pace)
        let entry = app.buttons["quality.carrierSpeed"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(ForumFixture.title("运营商测速", in: app).waitForExistence(timeout: 5))
        return app
    }

    func testCarrierSpeedRunsToAResult() {
        let app = openCarrierSpeed()
        // Carriers without a verified node are named in the footer rather than shown as dead rows.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '电信和移动节点验证后加入'")).firstMatch.exists)
        app.buttons["carrierSpeed.start"].tap()

        XCTAssertTrue(app.buttons["carrierSpeed.restart"].waitForExistence(timeout: 20))
        let download = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", "下载", "312 Mbps")).firstMatch
        XCTAssertTrue(download.exists)
        let latency = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '延迟 39 ms' AND label CONTAINS 'SpeedTest.cn'")).firstMatch
        XCTAssertTrue(latency.exists, "The latency line and the node's provider read together")
    }

    func testCarrierSpeedSaysWhichDirectionFailed() {
        let app = openCarrierSpeed(sample: "partialFailure")
        app.buttons["carrierSpeed.start"].tap()
        XCTAssertTrue(app.buttons["carrierSpeed.restart"].waitForExistence(timeout: 20))
        let upload = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '上传未测得：25 秒内未完成'")).firstMatch
        XCTAssertTrue(upload.exists)
    }

    func testLeavingCarrierSpeedStopsTheRun() {
        let app = openCarrierSpeed(pace: "0.9")
        app.buttons["carrierSpeed.start"].tap()
        XCTAssertTrue(app.buttons["carrierSpeed.cancel"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        // Back on the network check, nothing is left running. Reopening shows either a fresh card or the cancelled
        // result (SwiftUI may keep the page's state), never a run still going.
        let entry = app.buttons["quality.carrierSpeed"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quality.start"].isEnabled)
        entry.tap()
        let idle = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["carrierSpeed.start", "carrierSpeed.restart"])).firstMatch
        XCTAssertTrue(idle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["carrierSpeed.cancel"].exists)
    }

    func testDeviceBenchmarkRunsOffline() {
        let app = open("本机性能")
        app.buttons["benchmark.start"].tap()
        XCTAssertTrue(app.buttons["benchmark.restart"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["历史成绩"].exists || app.collectionViews.firstMatch.staticTexts["历史成绩"].exists)
    }
}
