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

    func testStreamingChecksRunOffline() {
        let app = open("网络检测")
        app.buttons["quality.start"].tap()
        XCTAssertFalse(app.buttons["quality.streaming"].exists, "The entry stays out of the way while a run is under way")
        XCTAssertTrue(app.buttons["quality.restart"].waitForExistence(timeout: 20))
        let entry = app.buttons["quality.streaming"]
        for _ in 0..<6 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(ForumFixture.title("流媒体", in: app).waitForExistence(timeout: 5))

        app.buttons["streaming.start"].tap()
        XCTAssertTrue(app.buttons["streaming.restart"].waitForExistence(timeout: 10))
        func row(_ words: String...) -> XCUIElement {
            let format = words.map { _ in "label CONTAINS %@" }.joined(separator: " AND ")
            return app.descendants(matching: .any).matching(NSPredicate(format: format, argumentArray: words)).firstMatch
        }
        XCTAssertTrue(row("Netflix", "片名页可访问").exists)
        XCTAssertTrue(row("Disney+", "HTTP 403", "无法判断").exists)
        XCTAssertTrue(row("TikTok", "超时").exists)

        // The sample players never load the network; one plays, the other reports blocked autoplay.
        app.buttons["streaming.play.youTube"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '已播放'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["streaming.playback.done"].tap()
        XCTAssertTrue(app.buttons["streaming.play.youTube"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["streaming.play.youTube"].label.contains("已播放"))
        app.buttons["streaming.play.tikTok"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '自动播放被拦'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["streaming.playback.done"].tap()
        XCTAssertTrue(app.buttons["streaming.play.tikTok"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["streaming.play.tikTok"].label.contains("自动播放被拦"))

        // The region form starts from the report's exit country and needs a key before it queries.
        let region = app.buttons["streaming.region"]
        for _ in 0..<4 where !region.isHittable { app.swipeUp() }
        region.tap()
        let country = app.textFields["region.country"]
        XCTAssertTrue(country.waitForExistence(timeout: 5))
        XCTAssertEqual(country.value as? String, "CN")
        let check = app.buttons["region.check"]
        XCTAssertFalse(check.isEnabled)
        let key = app.secureTextFields["region.key"]
        key.tap()
        key.typeText("offline-sample-key")
        XCTAssertTrue(check.isEnabled)
        check.tap()
        XCTAssertTrue(row("CN 的规则", "未发布地区规则").waitForExistence(timeout: 5))
    }

    func testDeviceBenchmarkRunsOffline() {
        let app = open("本机性能")
        app.buttons["benchmark.start"].tap()
        XCTAssertTrue(app.buttons["benchmark.restart"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["历史成绩"].exists || app.collectionViews.firstMatch.staticTexts["历史成绩"].exists)
    }
}
