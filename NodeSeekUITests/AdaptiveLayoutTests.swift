import XCTest

/// Checks docs/DESIGN.md rule 9 on whatever screen the tests run on — iPhone, iPad or a Mac window:
/// cards keep to one readable, centred column, the bars above and below them line up with that column,
/// and the hardware-keyboard shortcuts reach the new-post and reply actions.
@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    // Element frames are in screen points, so app sizes are scaled by `ForumFixture.pointScale`.
    /// Matches `SeekLayout.readableWidth` in the app.
    private let readableWidth = 760 * ForumFixture.pointScale
    /// Matches `SeekLayout.gutter` in the app.
    private let gutter = 16 * ForumFixture.pointScale
    /// How far the reply bar sits inside the cards.
    private let replyBarInset = 4 * ForumFixture.pointScale
    /// docs/DESIGN.md allows 2 points between gaps that should match.
    private let tolerance: CGFloat = 2

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .portrait
        #endif
        super.tearDown()
    }

    func testFeedKeepsAReadableCentredColumn() throws {
        let app = ForumFixture.launch()
        assertFeedColumn(in: app)
        attachScreenshot(of: app, named: "Feed")
    }

    /// Every tab stays on screen: in the tab bar on iPhone and iPad, in the sidebar on a Mac.
    func testAllTabsAreOnScreen() throws {
        let app = ForumFixture.launch()
        for name in ["社区", "通知", "我的"] {
            XCTAssertTrue(ForumFixture.tab(name, in: app).waitForExistence(timeout: 10), "The \(name) tab should be on screen.")
        }
    }

    #if !targetEnvironment(macCatalyst)
    func testFeedKeepsItsColumnInLandscape() throws {
        // Only iPad turns: iPhone keeps to portrait.
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Only iPad supports landscape.")
        let app = ForumFixture.launch()
        XCTAssertTrue(ForumFixture.postCard(ForumFixture.threadTitle, in: app).waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        // Let the rotation settle before measuring.
        Thread.sleep(forTimeInterval: 1)
        assertFeedColumn(in: app)
        attachScreenshot(of: app, named: "Feed in landscape")
    }
    #endif

    func testThreadCardsAndReplyBarShareOneColumn() throws {
        let app = ForumFixture.launchThread()
        let comment = ForumFixture.element("comment-2", in: app)
        let page = besideSidebar(app.scrollViews.containing(.any, identifier: "comment-2").firstMatch.frame, in: app)
        let card = comment.frame
        assertColumn(card, in: page, "Reply card")

        // The reply bar is inset 4 points inside the cards on every width.
        let reply = replyButton(in: app)
        let share = app.buttons["分享帖子"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertTrue(share.exists)
        assertClose(reply.frame.minX - card.minX, replyBarInset, "Reply bar leading edge")
        assertClose(card.maxX - share.frame.maxX, replyBarInset, "Reply bar trailing edge")
        attachScreenshot(of: app, named: "Thread")
    }

    #if targetEnvironment(macCatalyst)
    /// The Mac sidebar marks the open tab with the app's tint. In dark mode its label must still stand out
    /// from that highlight: an ink tint that turns white drew white text on a white bar.
    func testSidebarSelectionIsReadableInDarkMode() throws {
        for dark in [false, true] {
            let app = ForumFixture.launch(dark: dark)
            let selected = app.cells.matching(NSPredicate(format: "label == %@ AND isSelected == true", "社区")).firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 10), "The feed tab should be selected in the sidebar.")
            attachScreenshot(of: app, named: dark ? "Sidebar in dark mode" : "Sidebar in light mode")
            let contrast = try XCTUnwrap(ForumFixture.contrast(of: selected.screenshot().image))
            XCTAssertGreaterThan(contrast, 0.4, "The selected tab's label should stand out from its highlight (dark: \(dark)).")
            app.terminate()
        }
    }
    #endif

    func testGroupedListKeepsTheColumn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-offline"]
        app.launch()
        let account = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()

        let tools = app.cells.containing(.staticText, identifier: "社区工具").firstMatch
        let list = app.collectionViews.containing(.staticText, identifier: "社区工具").firstMatch
        ForumFixture.assertReadableRow(tools, in: list)
        attachScreenshot(of: app, named: "Account")
    }

    func testCommandNAsksASignedOutReaderToSignIn() throws {
        let app = ForumFixture.launch()
        XCTAssertTrue(app.buttons["发布帖子"].waitForExistence(timeout: 10))

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(ForumFixture.title("登录 NodeSeek", in: app).waitForExistence(timeout: 5),
                      "⌘N should start a new post, which asks a signed-out reader to sign in first.")
    }

    func testCommandRAsksASignedOutReaderToSignIn() throws {
        let app = ForumFixture.launchThread()
        let reply = replyButton(in: app)
        XCTAssertTrue(reply.wait(for: \.isEnabled, toEqual: true, timeout: 5))

        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(ForumFixture.title("登录 NodeSeek", in: app).waitForExistence(timeout: 5),
                      "⌘R should start a reply, which asks a signed-out reader to sign in first.")
    }

    // MARK: - Helpers

    private func assertFeedColumn(in app: XCUIApplication, line: UInt = #line) {
        let post = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
        XCTAssertTrue(post.waitForExistence(timeout: 10), line: line)
        let list = app.collectionViews
            .containing(NSPredicate(format: "label BEGINSWITH %@", ForumFixture.threadTitle)).firstMatch.frame
        // A feed card's button reports its whole list row: the card plus a gutter on each side.
        let row = post.frame
        let card = row.insetBy(dx: gutter, dy: 0)
        // A sidebar overlaps the list, so the filter bar below shows where the page beside it is centred.
        assertColumn(card, in: list, "Feed card", centred: !hasSidebar(app), line: line)

        // The filter bar above the cards lines up with them.
        let category = app.buttons["选择版块，当前全部"]
        let newPost = app.buttons["发布帖子"]
        XCTAssertTrue(category.exists, line: line)
        XCTAssertTrue(newPost.exists, line: line)
        assertClose(category.frame.minX, card.minX, "Category button and card leading edges", line: line)
        assertClose(newPost.frame.maxX, card.maxX, "New post button and card trailing edges", line: line)
    }

    /// A card fills the width up to `readableWidth` and sits in the middle of the page that scrolls it,
    /// which is the whole window on iPhone and iPad and the area beside the sidebar on a Mac.
    private func assertColumn(_ card: CGRect, in page: CGRect, _ name: String, centred: Bool = true, line: UInt = #line) {
        if centred {
            let expectedWidth = min(readableWidth, page.width - 2 * gutter)
            assertClose(card.width, expectedWidth, "\(name) width in a \(page.width)-point page", line: line)
            assertClose(card.minX - page.minX, page.maxX - card.maxX, "\(name) side gaps", line: line)
        } else {
            XCTAssertLessThanOrEqual(card.width, readableWidth + tolerance, "\(name) keeps to the readable width.", line: line)
        }
    }

    /// The Mac lists the tabs in a sidebar beside the page instead of a tab bar.
    private func hasSidebar(_ app: XCUIApplication) -> Bool {
        sidebarTab(in: app).exists
    }

    private func sidebarTab(in app: XCUIApplication) -> XCUIElement {
        app.cells.matching(NSPredicate(format: "label == %@", "社区")).firstMatch
    }

    /// The part of a page that a sidebar leaves free. The page runs on under the sidebar, but its cards
    /// centre in the area beside it.
    private func besideSidebar(_ page: CGRect, in app: XCUIApplication) -> CGRect {
        guard hasSidebar(app) else { return page }
        let sidebar = app.collectionViews.containing(.cell, identifier: sidebarTab(in: app).identifier).firstMatch.frame
        guard sidebar.maxX > page.minX, sidebar.maxX < page.maxX else { return page }
        return CGRect(x: sidebar.maxX, y: page.minY, width: page.maxX - sidebar.maxX, height: page.height)
    }

    private func replyButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["写回复", "登录后回复"])).firstMatch
    }

    private func assertClose(_ value: CGFloat, _ expected: CGFloat, _ name: String, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(value - expected), tolerance, "\(name): \(value) should be \(expected).", line: line)
    }

    /// Keeps a screenshot in the test report, so a run on each device shows how the page looks there.
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
