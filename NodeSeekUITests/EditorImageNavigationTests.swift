import XCTest

@MainActor
final class EditorImageNavigationTests: XCTestCase {
    func testEditorOpensAndCancelsTheSystemPhotoPicker() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": 190_314, "name": "测试用户"]],
            "responses": [
                "https://www.nodeseek.com/?sortBy=replyTime": Data(#"{"posts":[],"pinnedPosts":[],"hasNextPage":false}"#.utf8).base64EncodedString()
            ]
        ]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] =
            String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()

        let compose = app.buttons["发布帖子"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 8))
        compose.tap()
        let photos = app.buttons["选择图片"].firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 8))
        photos.tap()

        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "取消", "Close", "Cancel"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 12))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 20), "The system photo picker should dismiss after cancellation.")
        XCTAssertTrue(photos.wait(for: \.isHittable, toEqual: true, timeout: 12), "The editor should be ready after the picker closes.")
    }
}
