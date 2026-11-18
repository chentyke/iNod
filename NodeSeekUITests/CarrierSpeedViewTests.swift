import XCTest

/// The carrier speed page, driven by sample data so it runs offline.
@MainActor
final class CarrierSpeedViewTests: XCTestCase {
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
}
