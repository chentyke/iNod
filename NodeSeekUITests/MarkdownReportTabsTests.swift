import XCTest

@MainActor
final class MarkdownReportTabsTests: XCTestCase {
    func testReportTabsWithMixedSpacingSwitchContent() {
        continueAfterFailure = false
        let app = ForumFixture.launch(opensThread: true, openingMarkdown: """
        ## 合计
        - **¥12.94**

        :::: tabs
        ::: tab-item 🎬IP质量
        IP 质量报告
        :::
        :::tab-item  🌐网络质量
        网络质量报告
        :::
        ::::
        """)
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        let first = app.staticTexts["IP 质量报告"]
        let second = app.staticTexts["网络质量报告"]
        XCTAssertTrue(first.isHittable)
        XCTAssertFalse(second.exists)
        picker.buttons["🌐网络质量"].tap()
        XCTAssertTrue(second.isHittable)
        XCTAssertFalse(first.exists)
        picker.buttons["🎬IP质量"].tap()
        XCTAssertTrue(first.isHittable)
    }
}
