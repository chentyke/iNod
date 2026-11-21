import XCTest

@MainActor
final class PageSwipeTests: XCTestCase {
    func testSwipingLeftOnThreadOpensAuthorProfile() {
        continueAfterFailure = false
        let app = ForumFixture.launchThread()
        let thread = app.scrollViews.containing(.staticText, identifier: ForumFixture.threadTitle).firstMatch
        XCTAssertTrue(thread.exists)

        thread.swipeLeft()
        let profile = ForumFixture.title("个人主页", in: app)
        let openedProfile = profile.waitForExistence(timeout: 5)
        capture(app, named: "thread-swipe")
        XCTAssertTrue(openedProfile)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "周末读书会发起人"))
            .firstMatch.waitForExistence(timeout: 5))
        capture(app, named: "author-profile")

        profile.buttons.firstMatch.tap()
        XCTAssertTrue(thread.waitForExistence(timeout: 5))
    }

    func testSwipingAcrossInboxSwitchesBetweenNoticesAndMessages() {
        continueAfterFailure = false
        let app = openInbox()
        let emptyNotices = app.staticTexts["暂无互动通知"]
        XCTAssertTrue(emptyNotices.wait(for: \.isHittable, toEqual: true, timeout: 5))

        app.swipeLeft()
        let messagesSearch = app.textFields["搜索私聊或找人"]
        let openedMessages = messagesSearch.wait(for: \.isHittable, toEqual: true, timeout: 5)
        capture(app, named: "inbox-swipe")
        XCTAssertTrue(openedMessages)

        app.swipeRight()
        XCTAssertTrue(emptyNotices.wait(for: \.isHittable, toEqual: true, timeout: 5))
        capture(app, named: "activity-empty")
    }

    func testShortAndLongSwipesOnUnreadNoticeDoDifferentActions() {
        continueAfterFailure = false
        let app = openInbox(showsUnreadNotice: true)
        let row = app.cells.containing(.staticText, identifier: ForumFixture.threadTitle).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        capture(app, named: "unread-inbox")

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -85, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0)
        let markAsRead = app.buttons["标为已读"]
        let messagesSearch = app.textFields["搜索私聊或找人"]
        XCTAssertTrue(markAsRead.waitForExistence(timeout: 5))
        XCTAssertFalse(messagesSearch.isHittable)
        XCTAssertTrue(app.buttons["互动"].isSelected)

        row.swipeRight()
        XCTAssertFalse(markAsRead.exists)
        row.swipeLeft()
        XCTAssertTrue(messagesSearch.wait(for: \.isHittable, toEqual: true, timeout: 5))
    }

    func testInboxTabsCanBeTappedWithLargerTextInDarkMode() {
        continueAfterFailure = false
        let app = openInbox(showsUnreadNotice: true, dark: true,
                            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityLarge"])
        let activity = app.buttons["互动"]
        let messages = app.buttons["私聊"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        XCTAssertTrue(activity.isSelected)
        XCTAssertTrue(messages.isHittable)
        let notice = app.cells.containing(.staticText, identifier: ForumFixture.threadTitle).firstMatch
        XCTAssertTrue(notice.wait(for: \.isHittable, toEqual: true, timeout: 5))
        capture(app, named: "unread-inbox-dark-large-text")

        messages.tap()
        let messagesSearch = app.textFields["搜索私聊或找人"]
        XCTAssertTrue(messagesSearch.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertTrue(messages.isSelected)
        XCTAssertFalse(notice.isHittable)
        capture(app, named: "messages-dark-large-text")

        activity.tap()
        XCTAssertTrue(notice.wait(for: \.isHittable, toEqual: true, timeout: 5))
    }

    private func openInbox(showsUnreadNotice: Bool = false, dark: Bool = false,
                           extraArguments: [String] = []) -> XCUIApplication {
        let app = ForumFixture.launch(dark: dark, signedInAsAuthor: true, showsUnreadNotice: showsUnreadNotice,
                                      extraArguments: extraArguments)
        let notifications = ForumFixture.tab("通知", in: app)
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()
        return app
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
