import Network
import UIKit
import XCTest

@MainActor
final class ThreadHistoryTests: XCTestCase {
    private let title = "周末的读书计划"
    private let openingText = "周六下午两点开始读书。"
    private let timestamp = "2025-01-04T12:00:00.000Z"

    #if targetEnvironment(macCatalyst)
    func testHorizontalScrollSettlesOnAPinnedCard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture(showsCarousel: true)
        app.launchArguments += ["--ui-test-no-carousel-autoplay", "-appearance", "dark"]
        app.launch()

        let carousel = app.scrollViews.containing(NSPredicate(format: "label BEGINSWITH %@", "置顶，")).firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 10))
        let frame = carousel.frame
        let firstCard = carousel.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "置顶，\(title)")).firstMatch
        let lastCard = carousel.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "置顶，本月读书会公告")).firstMatch
        XCTAssertTrue(firstCard.wait(for: \.isHittable, toEqual: true, timeout: 5))
        let initialFrame = firstCard.frame
        XCTAssertEqual(initialFrame.midX, frame.midX, accuracy: 2)

        let center = firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.hover()
        center.scroll(byDeltaX: -initialFrame.width * 1.2, deltaY: 0)
        let centered = lastCard.wait(for: \.frame, toEqual: initialFrame, timeout: 4)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Pinned carousel after horizontal scroll"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(centered, "Scrolling back from the first card should center the last card. Actual frame: \(lastCard.frame)")
    }
    #endif

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

    private func startImageServer(size: CGSize = CGSize(width: 360, height: 610),
                                  responseDelay: DispatchTimeInterval = .milliseconds(350),
                                  responseSent: XCTestExpectation? = nil) throws -> NWListener {
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
                queue.asyncAfter(deadline: .now() + responseDelay) {
                    connection.send(content: response, completion: .contentProcessed { error in
                        if error == nil { responseSent?.fulfill() }
                        connection.cancel()
                    })
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
        let earlierReply = ForumFixture.element("comment-20", in: app)
        XCTAssertTrue(reveal(earlierReply, in: scrollView), "Scrolling back should load a reply from page 2.")
        XCTAssertTrue(ForumFixture.threadText(replyText(20), in: earlierReply).exists)

        let firstReply = ForumFixture.element("comment-1", in: app)
        XCTAssertTrue(reveal(firstReply, in: scrollView), "Scrolling further should reach page 1.")
        XCTAssertTrue(ForumFixture.threadText(replyText(1), in: firstReply).exists)

        let opening = ForumFixture.element("comment-0", in: app)
        XCTAssertTrue(reveal(opening, in: scrollView), "Page 1 should show the post body.")
        XCTAssertTrue(ForumFixture.threadText(openingText, in: opening).exists)
    }

    private func reveal(_ card: XCUIElement, in scrollView: XCUIElement) -> Bool {
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
        let frame = scrollView.frame
        let limit = frame.height / 3
        for _ in 0..<14 {
            let exists = card.exists
            if exists, card.isHittable { return true }
            // Use the card's frame and avoid overshooting it when the previous page appears.
            let distance = exists ? card.frame.midY - frame.midY : -limit
            let step = min(max(distance, -limit), limit)
            let destination = start.withOffset(CGVector(dx: 0, dy: -step))
            start.press(forDuration: 0, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        return card.exists && card.isHittable
    }

    private func replyText(_ floor: Int) -> String { "第 \(floor) 楼的回复" }

    private func websiteFixture(openingMarkdown: String? = nil, showsCarousel: Bool = false,
                                notificationFloor: Int = 22, pageCount: Int = 3) throws -> String {
        let pinnedPost: [String: Any] = ["id": 123, "title": title, "author": "楼主", "authorID": 101,
            "avatar": "", "category": "日常", "categoryKey": "daily", "views": 100, "replies": 30,
            "activityDate": timestamp, "pinned": true]
        var otherPost = pinnedPost
        otherPost["id"] = 124
        otherPost["title"] = "本月读书会公告"
        var responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [], "pinnedPosts": showsCarousel ? [pinnedPost, otherPost] : [pinnedPost],
                "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/notification/unread-count": ["unreadCount": ["all": 0]],
            "/api/notification/at-me/list": ["items": [], "hasNext": false],
            "/api/notification/reply-to-me/list": [
                "items": [["id": 1, "viewed": true, "postID": 123, "title": title, "floor": notificationFloor,
                           "authorID": 102, "author": "读者", "createdAt": timestamp]],
                "hasNext": false
            ],
            "https://www.nodeseek.com/post-123-1": threadPage(1, floors: 0...(pageCount == 1 ? 6 : 10),
                                                         openingMarkdown: openingMarkdown, pageCount: pageCount)
        ]
        if pageCount > 1 {
            responses["https://www.nodeseek.com/post-123-2"] = threadPage(2, floors: 11...20)
            responses["https://www.nodeseek.com/post-123-3"] = threadPage(3, floors: 21...30)
        }
        let fixture: [String: Any] = [
            "authentication": ["ready": true, "user": ["id": 101, "name": "楼主"]],
            "responses": try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
    }

    private func threadPage(_ page: Int, floors: ClosedRange<Int>, openingMarkdown: String? = nil, pageCount: Int = 3) -> [String: Any] {
        let author: [String: Any] = ["uid": 101, "name": "楼主"]
        let reader: [String: Any] = ["uid": 102, "name": "读者"]
        let comments: [[String: Any]] = floors.map { floor in
            ["commentId": 500 + floor, "floorIndex": floor, "poster": floor == 0 ? author : reader,
             "time": ["createdDate": timestamp], "markdown": floor == 0 ? openingMarkdown ?? openingText : replyText(floor),
             "likeCount": 0, "upvoteCount": 0, "blocked": false]
        }
        return ["postId": 123, "title": title, "categoryWord": "日常", "views": "100",
                "postPage": page, "postPageCount": pageCount, "collectionCount": 0, "op": author, "comments": comments]
    }

    func testColdLaunchOpensFirstNotificationAtReplyBelowLongPost() throws {
        continueAfterFailure = false
        let imageSent = XCTestExpectation(description: "Tall image response sent")
        let server = try startImageServer(size: CGSize(width: 360, height: 1500), responseDelay: .seconds(2),
                                          responseSent: imageSent)
        defer { server.cancel() }
        let port = try XCTUnwrap(server.port).rawValue
        let opening = ["# \(openingText)", "![读书会照片](http://127.0.0.1:\(port)/reading-group)"]
        let paragraphs = (1...12).map { section in
            "## 第 \(section) 段\n\n" + String(repeating: "我们读完这一章之后，会一起讨论书里提到的问题。", count: 5)
        }
        let markdown = (opening + paragraphs).joined(separator: "\n\n")
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try websiteFixture(openingMarkdown: markdown, notificationFloor: 5, pageCount: 1)
        app.launch()

        let notifications = ForumFixture.tab("通知", in: app)
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()

        let notice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", title, "回复了你")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        notice.tap()

        XCTAssertEqual(XCTWaiter.wait(for: [imageSent], timeout: 8), .completed)
        let text = replyText(5)
        let reply = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
        XCTAssertTrue(reply.wait(for: \.isHittable, toEqual: true, timeout: 5), "The reply should be visible without scrolling by hand.")
        XCTAssertLessThan(reply.frame.maxY, app.buttons["写回复"].frame.minY)
    }
}
