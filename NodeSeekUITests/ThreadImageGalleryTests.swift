import Network
import UIKit
import XCTest

@MainActor
final class ThreadImageGalleryTests: XCTestCase {
    func testOpeningAndSwipingThroughPostAndReplyImages() throws {
        continueAfterFailure = false
        let server = try imageServer()
        defer { server.cancel() }
        let port = try XCTUnwrap(server.port)
        let app = XCUIApplication()
        app.launchArguments += ["-showsBlockedContent", "NO"]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture(port: port.rawValue)
        app.launch()

        let post = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "周末照片")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 8))
        post.tap()

        let second = app.buttons["正文第二张"]
        XCTAssertTrue(second.waitForExistence(timeout: 8))
        second.tap()
        assertPicture("正文第二张", position: "第 2 张，共 5 张", in: app)

        let attribution = app.descendants(matching: .any)["image-gallery-attribution"].firstMatch
        XCTAssertTrue(attribution.label.contains("正文"))
        XCTAssertTrue(attribution.label.contains("楼主"))

        let image = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52))
        image.tap()
        XCTAssertTrue(app.buttons["完成"].waitForNonExistence(timeout: 3))
        image.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 3))
        image.doubleTap()
        swipeGallery(in: app, forward: false)
        assertPicture("正文第二张", position: "第 2 张，共 5 张", in: app)
        image.doubleTap()
        swipeGallery(in: app, forward: false)
        assertPicture("正文第一张", position: "第 1 张，共 5 张", in: app)
        swipeGallery(in: app, forward: true)
        swipeGallery(in: app, forward: true)
        assertPicture("第一条评论第一张", position: "第 3 张，共 5 张", in: app)
        attribution.tap()
        XCTAssertTrue(app.buttons["完成"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["第一条评论第一张"].isHittable)

        let reply = app.buttons["第一条评论第二张"]
        guard reveal(reply, in: app.scrollViews.firstMatch) else {
            return XCTFail("The reply image should be visible in the thread.")
        }
        reply.tap()
        assertPicture("第一条评论第二张", position: "第 4 张，共 5 张", in: app)
        XCTAssertTrue(attribution.label.contains("#1"))
        swipeGallery(in: app, forward: true)
        assertPicture("第二条评论第一张", position: "第 5 张，共 5 张", in: app)
        swipeGallery(in: app, forward: true)
        assertPicture("第二条评论第一张", position: "第 5 张，共 5 张", in: app)
        XCTAssertTrue(attribution.label.contains("#3"))
        XCTAssertTrue(attribution.label.contains("读者"))

        let current = app.images["第二条评论第一张"].firstMatch
        let fittedScale = try XCTUnwrap(current.value as? String)
        current.pinch(withScale: 2.5, velocity: 2)
        XCTAssertNotEqual(try XCTUnwrap(current.value as? String), fittedScale)
        current.swipeDown()
        assertPicture("第二条评论第一张", position: "第 5 张，共 5 张", in: app)
        image.doubleTap()
        XCTAssertEqual(current.value as? String, fittedScale)
        current.swipeDown()
        XCTAssertTrue(app.buttons["完成"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(reply.isHittable)
    }

    func testIncludesImagesAfterLoadingAnotherReplyPage() throws {
        continueAfterFailure = false
        let server = try imageServer()
        defer { server.cancel() }
        let port = try XCTUnwrap(server.port)
        let app = XCUIApplication()
        app.launchArguments += ["-showsBlockedContent", "NO"]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture(port: port.rawValue, paged: true)
        app.launch()

        let post = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "周末照片")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 8))
        post.tap()

        let laterImage = app.buttons["70157.png"]
        XCTAssertTrue(reveal(laterImage, in: app.scrollViews.firstMatch))
        laterImage.tap()
        assertPicture("70157.png", position: "第 5 张，共 5 张", in: app)
        let source = app.buttons["image-gallery-attribution"]
        XCTAssertTrue(source.label.contains("@admin 下山前拍到了最后一束光"))
        XCTAssertFalse(source.label.contains("70157.png"))
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "评论图片与楼层"
        preview.lifetime = .keepAlways
        add(preview)
        swipeGallery(in: app, forward: false)
        assertPicture("第一条评论第二张", position: "第 4 张，共 5 张", in: app)
        XCTAssertTrue(source.label.contains("周末照片"))
        XCTAssertFalse(source.label.contains("第一条评论第二张"))
        swipeGallery(in: app, forward: false)
        swipeGallery(in: app, forward: false)
        assertPicture("正文第二张", position: "第 2 张，共 5 张", in: app)
        app.buttons["image-gallery-attribution"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["正文第一张"].isHittable)
    }

    func testCollapsedCalloutsShowImagesAfterOpening() throws {
        continueAfterFailure = false
        let server = try imageServer()
        defer { server.cancel() }
        let port = try XCTUnwrap(server.port).rawValue
        let opening = """
        >[!note]- 选项1
        > ![选项一截图](http://127.0.0.1:\(port)/0)

        >[!note]- 选项2
        >![选项二截图](http://127.0.0.1:\(port)/1)

        猜猜哪个是对的
        """
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture(port: port, opening: opening)
        app.launch()
        let post = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "周末照片")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 8))
        post.tap()

        let first = app.buttons["选项1"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertEqual(first.value as? String, "已收起")
        XCTAssertTrue(app.buttons["选项2"].exists)
        XCTAssertTrue(app.staticTexts["猜猜哪个是对的"].exists)
        let marker = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "[!note]", "127.0.0.1")
        XCTAssertFalse(app.staticTexts.matching(marker).firstMatch.exists, "The callout syntax should not show as text.")
        XCTAssertFalse(app.buttons["选项一截图"].exists, "A collapsed callout should hide its image.")

        first.tap()
        XCTAssertEqual(first.value as? String, "已展开")
        let picture = app.buttons["选项一截图"]
        XCTAssertTrue(picture.wait(for: \.isHittable, toEqual: true, timeout: 8))
        XCTAssertFalse(app.buttons["选项二截图"].exists, "Opening one callout should leave the other folded.")
        picture.tap()
        assertPicture("选项一截图", position: "第 1 张，共 5 张", in: app)
        swipeGallery(in: app, forward: true)
        assertPicture("选项二截图", position: "第 2 张，共 5 张", in: app)
    }

    func testSavingAndSharingTheCurrentPicture() throws {
        continueAfterFailure = false
        let server = try imageServer()
        defer { server.cancel() }
        let port = try XCTUnwrap(server.port)
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture(port: port.rawValue)
        app.launchArguments += ["-showsBlockedContent", "NO"]
        app.launchEnvironment["NODESEEK_UI_TEST_OPEN_POST"] = "123"
        app.launch()

        let first = app.buttons["正文第一张"]
        XCTAssertTrue(first.waitForExistence(timeout: 12))
        first.tap()
        swipeGallery(in: app, forward: true)
        assertPicture("正文第二张", position: "第 2 张，共 5 张", in: app)
        app.buttons["保存图片"].tap()

        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            let allow = alert.buttons.matching(NSPredicate(format: "label IN %@",
                ["Allow", "允许", "好", "OK", "仅添加照片", "Allow Adding Photos"])).firstMatch
            XCTAssertTrue(allow.exists, alert.debugDescription)
            allow.tap()
        }
        XCTAssertTrue(app.buttons["已保存到相册"].waitForExistence(timeout: 8))
        swipeGallery(in: app, forward: true)
        XCTAssertTrue(app.buttons["保存图片"].isEnabled)
        app.buttons["分享图片"].tap()
        let sheet = app.descendants(matching: .any)["ActivityListView"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), app.debugDescription)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "分享当前图片"
        preview.lifetime = .keepAlways
        add(preview)
    }

    private func swipeGallery(in app: XCUIApplication, forward: Bool) {
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.55))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55))
        (forward ? right : left).press(forDuration: 0.05, thenDragTo: forward ? left : right,
                                       withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func assertPicture(_ label: String, position: String, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        let image = app.images[label].firstMatch
        XCTAssertTrue(image.wait(for: \.isHittable, toEqual: true, timeout: 5), file: file, line: line)
        XCTAssertEqual(app.descendants(matching: .any)["image-gallery-position"].firstMatch.value as? String,
                       position, file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
        for _ in 0..<5 {
            if element.exists, element.isHittable { return true }
            scrollView.swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }

    private func imageServer() throws -> NWListener {
        let colors: [UIColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple, .systemPink]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 360, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let images = colors.map { color in renderer.pngData {
            color.setFill()
            $0.fill(CGRect(origin: .zero, size: size))
        } }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "thread-image-gallery-test")
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                let path = request.split(separator: " ").dropFirst().first
                let index = path.flatMap { Int($0.dropFirst()) } ?? -1
                let image = images.indices.contains(index) ? images[index] : Data()
                let status = image.isEmpty ? "404 Not Found" : "200 OK"
                let header = "HTTP/1.1 \(status)\r\nContent-Type: image/png\r\nContent-Length: \(image.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(header.utf8) + image, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let ready = XCTestExpectation(description: "Image server ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: queue)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 4), .completed)
        return listener
    }

    private func websiteFixture(port: UInt16, opening: String? = nil, paged: Bool = false) throws -> String {
        let author: [String: Any] = ["uid": 101, "name": "楼主"]
        let reader: [String: Any] = ["uid": 102, "name": "读者"]
        let timestamp = "2025-01-04T12:00:00.000Z"
        func image(_ label: String, _ index: Int) -> String { "![\(label)](http://127.0.0.1:\(port)/\(index))" }
        func comment(_ floor: Int, _ markdown: String, blocked: Bool = false) -> [String: Any] {
            ["commentId": 500 + floor, "floorIndex": floor, "poster": floor == 0 ? author : reader,
             "time": ["createdDate": timestamp], "markdown": markdown, "likeCount": 0, "upvoteCount": 0, "blocked": blocked]
        }
        let comments = [
            comment(0, opening ?? image("正文第一张", 0) + "\n正文\n" + image("正文第二张", 1)),
            comment(1, image("第一条评论第一张", 2) + "\n" + image("第一条评论第二张", 3)),
            comment(2, image("被屏蔽的评论图片", 4), blocked: true),
            comment(3, paged ? image("70157.png", 4) + "\n\n@admin 下山前拍到了最后一束光。" : image("第二条评论第一张", 4))
        ]
        let feedPost: [String: Any] = ["id": 123, "title": "周末照片", "author": "楼主", "authorID": 101,
                                      "avatar": "", "category": "日常", "categoryKey": "daily", "views": 100,
                                      "replies": 3, "activityDate": timestamp, "pinned": false]
        var responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [feedPost], "pinnedPosts": [], "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/notification/unread-count": ["unreadCount": ["all": 0]],
            "https://www.nodeseek.com/post-123-1": ["postId": 123, "title": "周末照片", "categoryWord": "日常",
                "views": "100", "postPage": 1, "postPageCount": paged ? 2 : 1, "collectionCount": 0, "op": author,
                "comments": paged ? Array(comments.dropLast()) : comments]
        ]
        if paged {
            responses["https://www.nodeseek.com/post-123-2"] = [
                "postId": 123, "title": "周末照片", "categoryWord": "日常", "views": "100",
                "postPage": 2, "postPageCount": 2, "collectionCount": 0, "op": author, "comments": [comments[3]]
            ]
        }
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": 101, "name": "楼主"]],
            "responses": try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
    }
}
