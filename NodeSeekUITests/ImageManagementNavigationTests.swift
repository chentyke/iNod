import XCTest

@MainActor
final class ImageManagementNavigationTests: XCTestCase {
    func testMyTabOpensImageManagementAndCanCancelKeyRotation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": 190_315, "name": "测试用户"]],
            "responses": [
                "https://www.nodeseek.com/?sortBy=replyTime": Data(#"{"posts":[],"pinnedPosts":[],"hasNextPage":false}"#.utf8).base64EncodedString()
            ]
        ]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] =
            String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()

        let myTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(myTab.waitForExistence(timeout: 8))
        myTab.tap()
        let management = app.buttons["图片上传与管理"].firstMatch
        for _ in 0..<4 where !management.isHittable { app.swipeUp() }
        XCTAssertTrue(management.isHittable)
        management.tap()
        XCTAssertTrue(app.navigationBars["图片上传与管理"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["连接 NodeImage"].exists)

        app.buttons["更新密钥"].tap()
        let confirmation = app.alerts["更新 NodeImage 密钥？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["连接 NodeImage"].isHittable)
    }
}
