import XCTest
import UIKit

/// A forum, signed out unless a test asks otherwise, with one feed page and one thread, served offline through `NODESEEK_UI_TEST_WEBSITE`.
enum ForumFixture {
    static let threadTitle = "周末的读书计划"
    static let threadID = 123
    static let announcementTitle = "本月读书会公告"
    static let peerID = 102
    static let peerName = "读者"
    private static let timestamp = "2025-01-04T12:00:00.000Z"

    /// Launches the app on the fixture's feed, in dark mode when `dark` is set,
    /// signed in as the thread's author when `signedInAsAuthor` is set.
    @MainActor static func launch(dark: Bool = false, opensThread: Bool = false, opensSidebar: Bool = false,
                                  opensConversation: Bool = false, signedInAsAuthor: Bool = false,
                                  authorID: Int = 101, openingMarkdown: String = "周六下午两点开始读书。",
                                  assetResponses: [String: Data] = [:], replyDraft: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] = try? json(signedInAsAuthor: signedInAsAuthor, authorID: authorID,
                                                                    openingMarkdown: openingMarkdown, assetResponses: assetResponses, replyDraft: replyDraft)
        if opensThread { app.launchEnvironment["NODESEEK_UI_TEST_OPEN_POST"] = "\(threadID)" }
        if opensSidebar { app.launchArguments.append("--ui-test-open-sidebar") }
        if opensConversation { app.launchEnvironment["NODESEEK_UI_TEST_OPEN_CONVERSATION"] = "\(peerID):\(peerName)" }
        // `appearance` is the in-app appearance setting; an argument sets it for this launch only.
        app.launchArguments += ["-appearance", dark ? "dark" : "light"]
        app.launch()
        return app
    }

    /// Launches the app and opens the fixture's thread from the feed.
    ///
    /// UI tests can't click into the Mac app, so there the app opens the thread itself once the feed loads.
    @MainActor static func launchThread(dark: Bool = false, signedInAsAuthor: Bool = false) -> XCUIApplication {
        #if targetEnvironment(macCatalyst)
        let app = launch(dark: dark, opensThread: true, signedInAsAuthor: signedInAsAuthor)
        #else
        let app = launch(dark: dark, signedInAsAuthor: signedInAsAuthor)
        let post = postCard(threadTitle, in: app)
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        post.tap()
        #endif
        XCTAssertTrue(element("comment-2", in: app).waitForExistence(timeout: 8))
        return app
    }

    /// Launches the app signed in and opens the fixture's private conversation.
    @MainActor static func launchConversation(dark: Bool = false) -> XCUIApplication {
        #if targetEnvironment(macCatalyst)
        let app = launch(dark: dark, opensConversation: true, signedInAsAuthor: true)
        #else
        let app = launch(dark: dark, signedInAsAuthor: true)
        let notifications = tab("通知", in: app)
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()
        let messagesSegment = app.buttons["私聊"]
        XCTAssertTrue(messagesSegment.waitForExistence(timeout: 5))
        messagesSegment.tap()
        let row = app.cells.containing(.staticText, identifier: peerName).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        #endif
        XCTAssertTrue(element("message-704", in: app).waitForExistence(timeout: 8))
        return app
    }

    /// How many screen points one app point takes. The Mac app is scaled to match iPad, which draws it at 77%.
    static var pointScale: CGFloat {
        #if targetEnvironment(macCatalyst)
        0.77
        #else
        1
        #endif
    }

    /// A root tab. iPhone shows it in a tab bar, iPad in its adaptable tab bar or sidebar, and the Mac in a sidebar.
    @MainActor static func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let label = NSPredicate(format: "label == %@", name)
        #if targetEnvironment(macCatalyst)
        return app.descendants(matching: .any).matching(label).firstMatch
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            let types = [XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue]
            return app.descendants(matching: .any)
                .matching(NSPredicate(format: "elementType IN %@ AND label == %@", types, name))
                .firstMatch
        }
        return app.buttons.matching(label).firstMatch
        #endif
    }

    /// An element by identifier whatever its type: the Mac reports some views as groups where iOS has others.
    @MainActor static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// A page or sheet's title bar. iOS reports it as a navigation bar; the Mac may report it as a toolbar.
    @MainActor static func title(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let bars = [XCUIElement.ElementType.navigationBar, .toolbar].map(\.rawValue)
        return app.descendants(matching: .any).matching(NSPredicate(
            format: "elementType IN %@ AND (identifier == %@ OR label == %@)", bars, title, title)).firstMatch
    }

    @MainActor static func postCard(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    @MainActor static func assertReadableRow(
        _ row: XCUIElement, in list: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(row.waitForExistence(timeout: 5), file: file, line: line)
        let rowFrame = row.frame
        let listFrame = list.frame
        let readableWidth = 760 * pointScale
        let sideGap = max(16 * pointScale, ((listFrame.width - readableWidth) / 2).rounded(.down))
        let tolerance: CGFloat = 2
        XCTAssertLessThanOrEqual(rowFrame.width, readableWidth + tolerance, file: file, line: line)
        XCTAssertEqual(rowFrame.minX - listFrame.minX, sideGap, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(listFrame.maxX - rowFrame.maxX, sideGap, accuracy: tolerance, file: file, line: line)
    }

    /// How far apart the darkest and lightest parts of an image are, from 0 (one flat colour) to 1 (black on white).
    /// It skips the darkest and lightest 1% of pixels, so stray specks don't count; a short label covers only a few percent of its row.
    static func contrast(of image: UIImage) -> CGFloat? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, width * height > 0 else { return nil }
        var luminances: [CGFloat] = []
        luminances.reserveCapacity(width * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let red = 0.2126 * CGFloat(pixels[i])
            let green = 0.7152 * CGFloat(pixels[i + 1])
            let blue = 0.0722 * CGFloat(pixels[i + 2])
            luminances.append((red + green + blue) / 255)
        }
        luminances.sort()
        let low = luminances[luminances.count / 100], high = luminances[luminances.count * 99 / 100]
        return high - low
    }

    private static func json(signedInAsAuthor: Bool, authorID: Int, openingMarkdown: String, assetResponses: [String: Data], replyDraft: String?) throws -> String {
        let author: [String: Any] = ["uid": authorID, "name": "楼主"]
        let reader: [String: Any] = ["uid": 102, "name": "读者"]
        func post(_ id: Int, _ title: String) -> [String: Any] {
            ["id": id, "title": title, "author": "楼主", "authorID": authorID, "avatar": "", "category": "日常",
             "categoryKey": "daily", "views": 100, "replies": 6, "activityDate": timestamp, "pinned": false]
        }
        let replies: [[String: Any]] = (0...6).map { floor in
            ["commentId": 500 + floor, "floorIndex": floor, "poster": floor == 0 ? author : reader,
             "time": ["createdDate": timestamp], "markdown": floor == 0 ? openingMarkdown : "第 \(floor) 楼：一起读。",
             "likeCount": 0, "upvoteCount": 0, "blocked": false]
        }
        let posts = [post(threadID, threadTitle)] + (1...8).map { post(200 + $0, $0 == 1 ? announcementTitle : "读书笔记第 \($0) 篇") }
        let messages: [[String: Any]] = [
            ["id": 701, "senderID": peerID, "receiverID": 101, "content": "周六的读书会还有空位吗？我想带两本笔记过来一起交流。",
             "createdAt": "2025-01-04T12:01:00.000Z", "isMarkdown": false, "viewed": true],
            ["id": 702, "senderID": 101, "receiverID": peerID, "content": "有的，下午两点在老地方见，直接过来就好。",
             "createdAt": "2025-01-04T12:03:00.000Z", "isMarkdown": false, "viewed": true],
            ["id": 703, "senderID": peerID, "receiverID": 101, "content": "太好了，那我准时到。",
             "createdAt": "2025-01-04T12:04:00.000Z", "isMarkdown": false, "viewed": true],
            ["id": 704, "senderID": 101, "receiverID": peerID, "content": "路上注意安全，到了群里或者私信说一声。",
             "createdAt": "2025-01-04T12:05:00.000Z", "isMarkdown": false, "viewed": true]
        ]
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": posts, "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/notification/unread-count": ["unreadCount": ["all": 0]],
            "/api/notification/reply-to-me/list": ["items": [], "hasNext": false],
            "/api/notification/at-me/list": ["items": [], "hasNext": false],
            "/api/notification/message/list": [
                "items": [["id": peerID, "latestMessageID": 704, "name": peerName,
                           "preview": "路上注意安全，到了群里或者私信说一声。", "isMarkdown": false,
                           "createdAt": "2025-01-04T12:05:00.000Z", "viewed": true]],
                "hasNext": false
            ],
            "/api/notification/message/with/\(peerID)": [
                "peer": ["id": peerID, "name": peerName],
                "items": messages
            ],
            "https://www.nodeseek.com/post-123-1": ["postId": 123, "title": threadTitle, "categoryWord": "日常",
                "views": "100", "postPage": 1, "postPageCount": 1, "collectionCount": 0, "op": author,
                "comments": replies],
            "https://www.nodeseek.com/post-201-1": ["postId": 201, "title": announcementTitle, "categoryWord": "日常",
                "views": "100", "postPage": 1, "postPageCount": 1, "collectionCount": 0, "op": author,
                "comments": Array(replies.prefix(1))]
        ]
        let signedOut: [String: Any] = ["ready": true]
        let authorSignedIn: [String: Any] = ["ready": true, "user": ["id": authorID, "name": "楼主"]]
        let encodedResponses = try responses.mapValues { try JSONSerialization.data(withJSONObject: $0).base64EncodedString() }
        var fixture: [String: Any] = [
            "authentication": signedInAsAuthor ? authorSignedIn : signedOut,
            "responses": encodedResponses.merging(assetResponses.mapValues { $0.base64EncodedString() }) { response, _ in response }
        ]
        if let replyDraft { fixture["replyDraft"] = ["postID": threadID, "content": replyDraft] }
        return String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
    }
}
