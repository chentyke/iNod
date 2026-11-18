import UIKit
import XCTest

@MainActor
final class NodeImageLibraryViewTests: XCTestCase {
    private let readableWidth = 760 * ForumFixture.pointScale
    private let gutter = 16 * ForumFixture.pointScale
    private let tolerance: CGFloat = 2
    private let sampleKey = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"

    override func setUp() {
        continueAfterFailure = false
    }

    func testImageLibraryConnectsManagesOptionsGalleryGridBatchAndKeySheet() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchImageLibrary(userID: 9_910_001, connected: false)

        // 1. Disconnected state, readable column, and key rotation cancellation
        let connectCard = ForumFixture.element("nodeimage-connect-card", in: app)
        XCTAssertTrue(connectCard.waitForExistence(timeout: 5))
        let connectButton = ForumFixture.element("nodeimage-connect-button", in: app)
        XCTAssertTrue(connectButton.isHittable)
        XCTAssertTrue(ForumFixture.element("nodeimage-manual-key-row", in: app).exists)

        assertReadableColumn(elementID: "nodeimage-connect-card", in: app)

        let rotateRow = ForumFixture.element("nodeimage-rotate-key-row", in: app)
        XCTAssertTrue(rotateRow.isHittable)
        rotateRow.tap()
        let rotationAlert = app.alerts["更新 NodeImage 密钥？"]
        XCTAssertTrue(rotationAlert.waitForExistence(timeout: 5))
        rotationAlert.buttons["取消"].tap()
        XCTAssertTrue(connectButton.wait(for: \.isHittable, toEqual: true, timeout: 5))

        // 2. Connect to NodeImage and load uploaded images
        connectButton.tap()
        XCTAssertTrue(ForumFixture.element("nodeimage-upload-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["bench-latency-chart.png"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["4 张"].exists)
        XCTAssertTrue(app.staticTexts["PNG"].exists)
        assertReadableColumn(elementID: "nodeimage-upload-card", in: app)

        // 3. Upload options sheet updates live summary on the upload card
        let optionsButton = ForumFixture.element("nodeimage-options-button", in: app)
        XCTAssertTrue(optionsButton.isHittable)
        optionsButton.tap()
        XCTAssertTrue(ForumFixture.title("上传选项", in: app).waitForExistence(timeout: 5))

        let markdownFormat = ForumFixture.element("nodeimage-format-markdown", in: app)
        XCTAssertTrue(markdownFormat.waitForExistence(timeout: 5))
        markdownFormat.tap()

        ForumFixture.element("nodeimage-options-done", in: app).tap()
        let summary = ForumFixture.element("nodeimage-options-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("Markdown"))

        // 4. Full-screen multi-image gallery preview
        let firstPreview = ForumFixture.element("nodeimage-preview-img_104", in: app)
        XCTAssertTrue(firstPreview.wait(for: \.isHittable, toEqual: true, timeout: 5))
        firstPreview.tap()

        let galleryCounter = app.descendants(matching: .any)["image-gallery-position"].firstMatch
        XCTAssertTrue(galleryCounter.waitForExistence(timeout: 5))
        XCTAssertEqual(galleryCounter.value as? String, "第 1 张，共 4 张")
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(ForumFixture.title("图片上传与管理", in: app).waitForExistence(timeout: 5))

        // 5. Grid / List layout toggle
        let layoutToggle = ForumFixture.element("nodeimage-layout-toggle", in: app)
        XCTAssertTrue(layoutToggle.isHittable)
        layoutToggle.tap()
        XCTAssertTrue(ForumFixture.element("nodeimage-history-grid", in: app).waitForExistence(timeout: 5))
        layoutToggle.tap()
        XCTAssertTrue(ForumFixture.element("nodeimage-preview-img_104", in: app).waitForExistence(timeout: 5))

        // 6. Batch selection & deletion via floating bottom bar
        let selectToggle = ForumFixture.element("nodeimage-select-toggle", in: app)
        XCTAssertTrue(selectToggle.isHittable)
        selectToggle.tap()

        XCTAssertTrue(ForumFixture.element("nodeimage-selection-bar", in: app).waitForExistence(timeout: 5))
        ForumFixture.element("nodeimage-select-img_104", in: app).tap()
        ForumFixture.element("nodeimage-select-img_103", in: app).tap()
        XCTAssertTrue(app.staticTexts["已选 2 张"].exists)

        let batchDelete = ForumFixture.element("nodeimage-batch-delete", in: app)
        XCTAssertTrue(batchDelete.isHittable)
        batchDelete.tap()

        let deleteAlert = app.alerts["删除这 2 张图片？"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 5))
        deleteAlert.buttons["删除"].tap()

        XCTAssertTrue(app.staticTexts["2 张"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["bench-latency-chart.png"].exists)

        // 7. Key management sheet: masked key display, hex validation, and local key removal
        let keyButton = ForumFixture.element("nodeimage-key-button", in: app)
        XCTAssertTrue(keyButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        keyButton.tap()

        XCTAssertTrue(ForumFixture.title("密钥管理", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "a1b2••••8f90")).firstMatch.exists)

        let keyField = ForumFixture.element("nodeimage-key-field", in: app)
        XCTAssertTrue(keyField.waitForExistence(timeout: 5))
        keyField.tap()
        keyField.typeText("invalid")

        XCTAssertFalse(ForumFixture.element("nodeimage-save-key", in: app).isEnabled)
        XCTAssertTrue(app.staticTexts["密钥需为 32 至 128 位十六进制字符。"].waitForExistence(timeout: 3))

        let removeButton = ForumFixture.element("nodeimage-remove-key", in: app)
        for _ in 0..<3 where !(removeButton.exists && removeButton.isHittable) { app.swipeUp() }
        XCTAssertTrue(removeButton.isHittable)
        removeButton.tap()

        let removeAlert = app.alerts["移除本机密钥？"]
        XCTAssertTrue(removeAlert.waitForExistence(timeout: 5))
        removeAlert.buttons["移除本机密钥"].tap()

        XCTAssertTrue(ForumFixture.element("nodeimage-connect-card", in: app).waitForExistence(timeout: 5))
        #endif
    }

    // MARK: - Helpers

    private func assertReadableColumn(elementID: String, in app: XCUIApplication, line: UInt = #line) {
        let list = app.collectionViews.containing(.any, identifier: elementID).firstMatch
        let card = list.cells.containing(.any, identifier: elementID).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), line: line)
        let listFrame = list.frame
        let rowFrame = card.frame
        XCTAssertLessThanOrEqual(rowFrame.width, readableWidth + tolerance, "Card keeps to readable width.", line: line)
        let expectedSideGap = max(gutter, ((listFrame.width - readableWidth) / 2).rounded(.down))
        XCTAssertLessThanOrEqual(abs((rowFrame.minX - listFrame.minX) - expectedSideGap), tolerance, line: line)
        XCTAssertLessThanOrEqual(abs((listFrame.maxX - rowFrame.maxX) - expectedSideGap), tolerance, line: line)
    }

    private func launchImageLibrary(userID: Int, connected: Bool) throws -> XCUIApplication {
        let app = XCUIApplication()
        let images: [[String: Any]] = [
            [
                "image_id": "img_104",
                "filename": "bench-latency-chart.png",
                "url": "https://cdn.nodeimage.com/i/bench-latency-chart.png",
                "upload_time": "2026-11-18T01:40:00.000Z"
            ],
            [
                "image_id": "img_103",
                "filename": "tokyo-route-trace.jpg",
                "url": "https://cdn.nodeimage.com/i/tokyo-route-trace.jpg",
                "upload_time": "2026-11-17T15:12:00.000Z"
            ],
            [
                "image_id": "img_102",
                "filename": "desk-setup-2026.png",
                "url": "https://cdn.nodeimage.com/i/desk-setup-2026.png",
                "upload_time": "2026-11-16T09:25:00.000Z"
            ],
            [
                "image_id": "img_101",
                "filename": "rack-topology-v2.png",
                "url": "https://cdn.nodeimage.com/i/rack-topology-v2.png",
                "upload_time": "2026-11-12T20:05:00.000Z"
            ]
        ]
        let responses: [String: String] = [
            "https://www.nodeseek.com/?sortBy=replyTime": try jsonBase64(["posts": [], "pinnedPosts": [], "hasNextPage": false]),
            "/api/content/list-categories": try jsonBase64(["success": true, "data": []]),
            "https://api.nodeimage.com/api/user/api-key": try jsonBase64(["api_key": sampleKey]),
            "POST https://api.nodeimage.com/api/user/regenerate-api-key": try jsonBase64(["api_key": String(repeating: "b", count: 64)]),
            "https://api.nodeimage.com/api/v1/images": try jsonBase64(["images": images]),
            "https://cdn.nodeimage.com/i/bench-latency-chart.png": samplePNG(
                color: UIColor(red: 0.16, green: 0.45, blue: 0.78, alpha: 1),
                accent: UIColor(red: 0.36, green: 0.72, blue: 0.96, alpha: 1)
            ),
            "https://cdn.nodeimage.com/i/tokyo-route-trace.jpg": samplePNG(
                color: UIColor(red: 0.15, green: 0.56, blue: 0.44, alpha: 1),
                accent: UIColor(red: 0.45, green: 0.85, blue: 0.68, alpha: 1)
            ),
            "https://cdn.nodeimage.com/i/desk-setup-2026.png": samplePNG(
                color: UIColor(red: 0.76, green: 0.43, blue: 0.20, alpha: 1),
                accent: UIColor(red: 0.95, green: 0.72, blue: 0.42, alpha: 1)
            ),
            "https://cdn.nodeimage.com/i/rack-topology-v2.png": samplePNG(
                color: UIColor(red: 0.38, green: 0.32, blue: 0.68, alpha: 1),
                accent: UIColor(red: 0.68, green: 0.62, blue: 0.94, alpha: 1)
            )
        ]
        var fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": userID, "name": "测试用户", "coins": 1280, "stardust": 155]],
            "responses": responses
        ]
        if connected {
            fixture["nodeImageKey"] = sampleKey
        }
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] =
            String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()

        let myTab = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(myTab.waitForExistence(timeout: 8))
        myTab.tap()

        // Wait for the signed-in identity header before checking whether "图片上传与管理" needs a scroll.
        XCTAssertTrue(app.staticTexts["测试用户"].waitForExistence(timeout: 5))
        let management = app.buttons["图片上传与管理"].firstMatch
        for _ in 0..<3 where !(management.exists && management.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(management.waitForExistence(timeout: 5))
        management.tap()
        XCTAssertTrue(ForumFixture.title("图片上传与管理", in: app).waitForExistence(timeout: 5))
        return app
    }

    private func jsonBase64(_ object: [String: Any]) throws -> String {
        try JSONSerialization.data(withJSONObject: object).base64EncodedString()
    }

    private func samplePNG(color: UIColor, accent: UIColor) -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 320, height: 240)
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            accent.setFill()
            UIBezierPath(roundedRect: CGRect(x: 28, y: 36, width: 180, height: 28), cornerRadius: 14).fill()
            UIBezierPath(roundedRect: CGRect(x: 28, y: 84, width: 264, height: 116), cornerRadius: 18).fill()
        }
        return data.base64EncodedString()
    }
}
