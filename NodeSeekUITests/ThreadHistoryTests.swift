import Network
import UIKit
import XCTest

@MainActor
final class ThreadHistoryTests: XCTestCase {
    private let title = "周末的读书计划"
    private let openingText = "周六下午两点开始读书。"
    private let timestamp = "2025-01-04T12:00:00.000Z"

    func testOpeningLongPinnedPostShowsTheWholeBeginning() throws {
        continueAfterFailure = false
        let server = try startImageServer()
        defer { server.cancel() }
        let port = try XCTUnwrap(server.port).rawValue
        let pictures = (1...14).map { "![插图 \($0)](http://127.0.0.1:\(port)/\($0))" }
        let sections = (1...15).map { "## 第 \($0) 段\n\n这是段落的内容。" }
        let paragraph = String(repeating: "这周会和大家分享读书笔记，欢迎在评论里一起讨论。", count: 5)
        let markdown = (["# \(openingText)", paragraph] + pictures + sections).joined(separator: "\n\n")
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture(openingMarkdown: markdown, showsCarousel: true)
        // The carousel turns every 6 seconds. On a busy CI runner the tap below took about 9 seconds
        // from locating this card to touching the screen, so it opened the next pinned post instead.
        app.launchArguments.append("--ui-test-no-carousel-autoplay")
        app.launch()

        let post = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "置顶，\(title)")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        post.tap()

        let threadScroll = app.scrollViews.containing(.any, identifier: "post-selectable-text")
            .containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(threadScroll.waitForExistence(timeout: 10), "Tapping the pinned card should open that post.")
        let heading = threadScroll.staticTexts[title].firstMatch
        let opening = ForumFixture.threadText(openingText, in: threadScroll)
        let firstImage = threadScroll.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "插图 1")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(firstImage.waitForExistence(timeout: 8), "The first thumbnail should finish loading.")
        let topBarButton = app.buttons["返回"].exists ? app.buttons["返回"] : app.buttons["更多"]
        XCTAssertTrue(topBarButton.exists)
        XCTAssertGreaterThanOrEqual(heading.frame.minY, topBarButton.frame.maxY, "The full post title should be visible on entry.")
        XCTAssertGreaterThan(opening.frame.minY, heading.frame.maxY, "The opening heading should follow the full title.")
    }

    private func startImageServer() throws -> NWListener {
        let size = CGSize(width: 360, height: 610)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).pngData {
            UIColor.systemBlue.setFill()
            $0.fill(CGRect(origin: .zero, size: size))
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(image.count)\r\nConnection: close\r\n\r\n"
        let response = Data(header.utf8) + image
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "long-post-test-images")
        server.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                queue.asyncAfter(deadline: .now() + .milliseconds(350)) {
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        let ready = XCTestExpectation(description: "Image server ready")
        server.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        server.start(queue: queue)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 4), .completed)
        return server
    }

    func testReplyNotificationCanScrollBackToEarlierPagesAndPostBody() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture()
        app.launch()

        let notifications = ForumFixture.tab("通知", in: app)
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()

        // iPad keeps the other tabs in the accessibility tree, so match the notice, not the feed's card for the same post.
        let notice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", title, "回复了你")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        notice.tap()

        let scrollView = app.scrollViews.firstMatch
        let targetReply = ForumFixture.threadText(replyText(22), in: app)
        XCTAssertTrue(targetReply.waitForExistence(timeout: 5))
        XCTAssertTrue(targetReply.isHittable, "The notification should open at the reply on page 3.")

        scrollView.swipeDown(velocity: .slow)
        let earlierReply = ForumFixture.threadText(replyText(20), in: app)
        XCTAssertTrue(reveal(earlierReply, in: scrollView), "Scrolling back should load a reply from page 2.")
        XCTAssertTrue(reveal(ForumFixture.threadText(replyText(1), in: app), in: scrollView), "Scrolling further should reach page 1.")
        XCTAssertTrue(reveal(ForumFixture.threadText(openingText, in: app), in: scrollView), "Page 1 should show the post body.")
    }

    private func reveal(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return true }
            if element.exists, element.frame.minY > scrollView.frame.midY {
                scrollView.swipeUp(velocity: .slow)
            } else {
                scrollView.swipeDown(velocity: .slow)
            }
        }
        return element.exists && element.isHittable
    }

    private func replyText(_ floor: Int) -> String { "第 \(floor) 楼的回复" }

    private func websiteFixture(openingMarkdown: String? = nil, showsCarousel: Bool = false) throws -> String {
        let pinnedPost: [String: Any] = ["id": 123, "title": title, "author": "楼主", "authorID": 101,
            "avatar": "", "category": "日常", "categoryKey": "daily", "views": 100, "replies": 30,
            "activityDate": timestamp, "pinned": true]
        var otherPost = pinnedPost
        otherPost["id"] = 124
        otherPost["title"] = "本月读书会公告"
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [], "pinnedPosts": showsCarousel ? [pinnedPost, otherPost] : [pinnedPost],
                "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/notification/unread-count": ["unreadCount": ["all": 0]],
            "/api/notification/at-me/list": ["items": [], "hasNext": false],
            "/api/notification/reply-to-me/list": [
                "items": [["id": 1, "viewed": true, "postID": 123, "title": title, "floor": 22,
                           "authorID": 102, "author": "读者", "createdAt": timestamp]],
                "hasNext": false
            ],
            "https://www.nodeseek.com/post-123-1": threadPage(1, floors: 0...10, openingMarkdown: openingMarkdown),
            "https://www.nodeseek.com/post-123-2": threadPage(2, floors: 11...20),
            "https://www.nodeseek.com/post-123-3": threadPage(3, floors: 21...30)
        ]
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": 101, "name": "楼主"]],
            "responses": try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
    }

    private func threadPage(_ page: Int, floors: ClosedRange<Int>, openingMarkdown: String? = nil) -> [String: Any] {
        let author: [String: Any] = ["uid": 101, "name": "楼主"]
        let reader: [String: Any] = ["uid": 102, "name": "读者"]
        let comments: [[String: Any]] = floors.map { floor in
            ["commentId": 500 + floor, "floorIndex": floor, "poster": floor == 0 ? author : reader,
             "time": ["createdDate": timestamp], "markdown": floor == 0 ? openingMarkdown ?? openingText : replyText(floor),
             "likeCount": 0, "upvoteCount": 0, "blocked": false]
        }
        return ["postId": 123, "title": title, "categoryWord": "日常", "views": "100",
                "postPage": page, "postPageCount": 3, "collectionCount": 0, "op": author, "comments": comments]
    }
}
