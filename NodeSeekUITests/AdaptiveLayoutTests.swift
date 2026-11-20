import XCTest

/// Checks docs/DESIGN.md rule 9 on whatever screen the tests run on — iPhone, iPad or a Mac window:
/// iPhone keeps cards in one readable, centred column, iPad and wide Mac windows split the community home into a
/// feed column beside a readable thread column, the Mac keeps new post in its sidebar and page actions in its window toolbar,
/// and hardware-keyboard shortcuts reach new-post and reply.
@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    // Element frames are in screen points, so app sizes are scaled by `ForumFixture.pointScale`.
    /// Matches `SeekLayout.readableWidth` in the app.
    private let readableWidth = 760 * ForumFixture.pointScale
    /// Matches `SeekLayout.gutter` in the app.
    private let gutter = 16 * ForumFixture.pointScale
    /// Matches the feed pane limits in `FeedSplitLayout`.
    private let minimumFeedPaneWidth = 336 * ForumFixture.pointScale
    private let maximumFeedPaneWidth = 400 * ForumFixture.pointScale
    /// How far the reply bar sits inside the cards.
    private let replyBarInset = 4 * ForumFixture.pointScale
    /// docs/DESIGN.md allows 2 points between gaps that should match.
    private let tolerance: CGFloat = 2

    private var isPadSplit: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    /// The Mac puts new post in its sidebar, and the category filter, search, reply and share in its window toolbar,
    /// instead of bars on the page.
    private var usesMacToolbar: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// Whether the community home shows the feed and reader side by side. A Mac window splits once it is wide enough.
    private func isSplit(_ app: XCUIApplication) -> Bool {
        if isPadSplit { return true }
        return ForumFixture.element("feed-detail-placeholder", in: app).exists
            || ForumFixture.postCard(ForumFixture.threadTitle, in: app).exists && ForumFixture.element("comment-2", in: app).exists
    }

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
        assertFeedLayout(in: app)
        attachScreenshot(of: app, named: "Feed")
    }

    /// Every tab stays on screen: in the tab bar on iPhone, in the adaptable bar/sidebar on iPad, in the sidebar on a Mac.
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
        let post = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        // Let the rotation settle before measuring.
        Thread.sleep(forTimeInterval: 1)
        assertSplitFeed(in: app)
        attachScreenshot(of: app, named: "Feed in landscape (empty)")

        post.tap()
        let comment = ForumFixture.element("comment-2", in: app)
        XCTAssertTrue(comment.waitForExistence(timeout: 8))
        XCTAssertTrue(post.isSelected, "The opened post card should stay marked as selected in the feed column.")
        XCTAssertFalse(ForumFixture.element("feed-detail-placeholder", in: app).exists)

        let list = feedListFrame(in: app)
        let detailScroll = app.scrollViews.containing(.any, identifier: "comment-2").firstMatch.frame
        XCTAssertGreaterThanOrEqual(detailScroll.minX, list.maxX - tolerance,
                                    "The thread pane should sit to the right of the feed column.")

        let card = comment.frame
        assertColumn(card, in: detailScroll, "Landscape split reply card")

        let author = app.buttons["查看 楼主 的主页"]
        let more = app.buttons["更多"]
        XCTAssertTrue(author.exists)
        XCTAssertTrue(more.exists)
        let community = ForumFixture.tab("社区", in: app)
        if !hasSidebar(app) {
            assertClose(author.frame.midY, community.frame.midY, "Author and tabs share a row")
            assertClose(more.frame.midY, community.frame.midY, "Menu and tabs share a row")
            XCTAssertLessThan(author.frame.maxX, community.frame.minX)
            XCTAssertLessThan(ForumFixture.tab("我的", in: app).frame.maxX, more.frame.minX)
        }
        assertClose(author.frame.minX, card.minX, "Thread author bar leading edge")
        assertClose(more.frame.maxX, card.maxX, "Thread menu button trailing edge")

        let reply = replyButton(in: app)
        let share = app.buttons["分享帖子"]
        XCTAssertTrue(reply.exists)
        XCTAssertTrue(share.exists)
        assertClose(reply.frame.minX - card.minX, replyBarInset, "Reply bar leading edge")
        assertClose(card.maxX - share.frame.maxX, replyBarInset, "Reply bar trailing edge")
        attachScreenshot(of: app, named: "Feed in landscape")

        // Use the system toggle in both directions while a post is open.
        let toggle = app.buttons.matching(NSPredicate(
            format: "identifier ==[c] %@ OR label IN %@",
            "ToggleSidebar", ["开关边栏", "隐藏边栏", "Toggle Sidebar", "Hide Sidebar"]
        )).firstMatch
        if hasSidebar(app) { toggle.tap() }
        XCTAssertTrue(sidebarTab(in: app).waitForNonExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(sidebarTab(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(post.isSelected)
        toggle.tap()
        XCTAssertTrue(sidebarTab(in: app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(post.isSelected)
        assertClose(author.frame.midY, community.frame.midY, "Author and tabs after collapsing sidebar")

        ForumFixture.tab("通知", in: app).tap()
        community.tap()
        XCTAssertTrue(post.isSelected)
        more.tap()
        let close = app.buttons["关闭帖子"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(ForumFixture.element("feed-detail-placeholder", in: app).waitForExistence(timeout: 5))
    }

    func testWideScreenSwitchesAndClosesPosts() throws {
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        let app = ForumFixture.launch()
        try XCTSkipUnless(app.windows.firstMatch.frame.width >= 720, "Requires a wide reading window.")
        let firstPost = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
        let secondPost = ForumFixture.postCard(ForumFixture.announcementTitle, in: app)
        let placeholder = ForumFixture.element("feed-detail-placeholder", in: app)
        XCTAssertTrue(firstPost.waitForExistence(timeout: 10))
        XCTAssertTrue(placeholder.exists)

        firstPost.tap()
        XCTAssertTrue(app.staticTexts["周六下午两点开始读书。"].waitForExistence(timeout: 8))
        XCTAssertTrue(firstPost.isSelected)
        XCTAssertFalse(placeholder.exists)
        let reader = ForumFixture.element("comment-2", in: app)
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(firstPost.frame.maxX, reader.frame.minX)
        attachScreenshot(of: app, named: "Expanded thread")

        secondPost.tap()
        XCTAssertTrue(app.staticTexts[ForumFixture.announcementTitle].waitForExistence(timeout: 8))
        XCTAssertTrue(secondPost.isSelected)
        XCTAssertFalse(firstPost.isSelected)

        let more = app.buttons["更多"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let close = app.buttons["关闭帖子"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
        XCTAssertFalse(secondPost.isSelected)
    }

    func testPadSidebarSelectionIsReadableInDarkMode() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Only iPad uses the adaptable sidebar here.")
        XCUIDevice.shared.orientation = .landscapeLeft
        for dark in [false, true] {
            let app = ForumFixture.launch(dark: dark, opensSidebar: true)
            let selected = app.cells.matching(NSPredicate(format: "label == %@ AND isSelected == true", "社区")).firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 10), "The feed tab should be selected in the iPad sidebar.")
            Thread.sleep(forTimeInterval: 0.6)
            assertSplitFeed(in: app)
            attachScreenshot(of: app, named: dark ? "iPad sidebar in dark mode" : "iPad sidebar in light mode")
            let contrast = try XCTUnwrap(ForumFixture.contrast(of: selected.screenshot().image))
            XCTAssertGreaterThan(contrast, 0.4, "The selected tab's label should stand out from its highlight (dark: \(dark)).")
            app.terminate()
        }
    }
    #endif

    func testThreadCardsAndReplyBarShareOneColumn() throws {
        let app = ForumFixture.launchThread()
        let comment = ForumFixture.element("comment-2", in: app)
        let scroll = app.scrollViews.containing(.any, identifier: "comment-2").firstMatch.frame
        let split = isSplit(app)
        let page = split ? scroll : besideSidebar(scroll, in: app)
        let card = comment.frame
        if split && !usesMacToolbar && !isPadSplit {
            // The native split view extends the scroller under the list and the vertical system bar.
            XCTAssertLessThanOrEqual(card.width, readableWidth + tolerance)
        } else {
            assertColumn(card, in: page, "Reply card")
        }

        if split {
            let feedCard = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
            XCTAssertTrue(feedCard.exists, "The feed column remains visible beside an open thread.")
            XCTAssertLessThanOrEqual(feedCard.frame.maxX, card.minX + tolerance)
        }

        if usesMacToolbar {
            // No reply bar floats over the page: reply and share sit in the window toolbar, above the cards.
            let reply = replyButton(in: app)
            XCTAssertTrue(reply.waitForExistence(timeout: 5), "The Mac toolbar should offer reply.")
            // The scroll view runs on under the transparent toolbar, so compare with the cards it shows.
            XCTAssertLessThanOrEqual(reply.frame.maxY, card.minY + tolerance)
            attachScreenshot(of: app, named: "Thread")
            return
        }

        // The reply bar is inset 4 points inside the cards on every width.
        let reply = replyButton(in: app)
        let share = app.buttons["分享帖子"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertTrue(share.exists)
        assertClose(reply.frame.minX - card.minX, replyBarInset, "Reply bar leading edge")
        assertClose(card.maxX - share.frame.maxX, replyBarInset, "Reply bar trailing edge")
        attachScreenshot(of: app, named: "Thread")
    }

    func testConversationBubblesAndComposerShareOneColumn() throws {
        #if targetEnvironment(macCatalyst)
        let app = ForumFixture.launchConversation(dark: true)
        #else
        let app = ForumFixture.launchConversation()
        #endif
        let incoming = ForumFixture.element("message-703", in: app)
        let outgoing = ForumFixture.element("message-704", in: app)
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        XCTAssertTrue(outgoing.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Conversation")

        let page = besideSidebar(app.scrollViews.containing(.any, identifier: "message-703").firstMatch.frame, in: app)
        let column = CGRect(x: incoming.frame.minX, y: incoming.frame.minY,
                            width: outgoing.frame.maxX - incoming.frame.minX, height: incoming.frame.height)
        assertColumn(column, in: page, "Conversation column")

        let options = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "私信选项")).firstMatch
        let send = app.buttons["发送"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertTrue(send.exists)
        assertClose(options.frame.minX, column.minX, "Incoming bubble and composer leading edges")
        assertClose(send.frame.maxX, column.maxX, "Outgoing bubble and composer trailing edges")
    }

    #if targetEnvironment(macCatalyst)
    func testSidebarTitlesAlignWithAnAccountAvatar() throws {
        let size = CGSize(width: 28, height: 28)
        let avatar = UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let app = ForumFixture.launch(
            signedInAsAuthor: true,
            assetResponses: ["https://www.nodeseek.com/avatar/101.png": avatar]
        )
        let names = ["社区", "通知", "我的"]
        let rows = names.map { app.cells[$0] }
        for (name, row) in zip(names, rows) {
            XCTAssertTrue(row.staticTexts[name].waitForExistence(timeout: 10))
        }
        let accountIcon = rows[2].images.firstMatch
        XCTAssertTrue(accountIcon.waitForExistence(timeout: 5))
        // The placeholder has the SF Symbol's identifier. The downloaded avatar is an unnamed image.
        XCTAssertTrue(accountIcon.wait(for: \.identifier, toEqual: "", timeout: 10), "The test avatar should load.")
        attachScreenshot(of: app, named: "Sidebar with an account avatar")

        let titleX = rows[0].staticTexts[names[0]].frame.minX
        let iconX = rows[0].images.firstMatch.frame.midX
        for (name, row) in zip(names.dropFirst(), rows.dropFirst()) {
            XCTAssertEqual(row.staticTexts[name].frame.minX, titleX, accuracy: 1, "\(name) title should share the same leading edge.")
            XCTAssertEqual(row.images.firstMatch.frame.midX, iconX, accuracy: 1, "\(name) icon should share the same horizontal centre.")
        }
    }

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

    func testMenuBarIncludesManualRefreshCommand() throws {
        #if targetEnvironment(macCatalyst)
        let app = ForumFixture.launchConversation(dark: true)
        let refreshItem = app.menuBars.menuBarItems["显示"].menus.menuItems["刷新"]
        XCTAssertTrue(refreshItem.waitForExistence(timeout: 5), "The View menu should expose a Refresh command on Mac.")
        XCTAssertTrue(refreshItem.isEnabled, "The Refresh command should be enabled while a refreshable page is open.")
        #else
        let app = ForumFixture.launchThread()
        XCTAssertTrue(replyButton(in: app).wait(for: \.isEnabled, toEqual: true, timeout: 5))
        app.typeKey("r", modifierFlags: [.command, .shift])
        XCTAssertTrue(ForumFixture.element("comment-2", in: app).waitForExistence(timeout: 5),
                      "⇧⌘R should reload the open thread in place without opening the reply sheet.")
        XCTAssertFalse(ForumFixture.title("登录 NodeSeek", in: app).exists)
        #endif
    }

    // MARK: - Helpers

    private func assertFeedLayout(in app: XCUIApplication, line: UInt = #line) {
        let post = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
        XCTAssertTrue(post.waitForExistence(timeout: 10), line: line)
        if isSplit(app) {
            assertSplitFeed(in: app, line: line)
        } else {
            assertSingleColumnFeed(in: app, line: line)
        }
    }

    private func assertSingleColumnFeed(in app: XCUIApplication, line: UInt = #line) {
        let post = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
        XCTAssertTrue(post.waitForExistence(timeout: 10), line: line)
        let list = feedListFrame(in: app)
        // A feed card's button reports its whole list row: the card plus a gutter on each side.
        let row = post.frame
        let card = row.insetBy(dx: gutter, dy: 0)
        // A sidebar overlaps the list, so the filter bar below shows where the page beside it is centred.
        assertColumn(card, in: list, "Feed card", centred: !hasSidebar(app), line: line)
        assertFilterBarAligns(with: card, in: app, line: line)
    }

    private func assertSplitFeed(in app: XCUIApplication, line: UInt = #line) {
        let post = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
        XCTAssertTrue(post.waitForExistence(timeout: 10), line: line)
        // When the adaptable sidebar is open, the feed list runs under it in the leading safe area;
        // measure the visible pane beside the sidebar.
        let list = besideSidebar(feedListFrame(in: app), in: app)
        let available = besideSidebar(app.windows.firstMatch.frame, in: app)
        let expectedFeedWidth = min(maximumFeedPaneWidth, max(minimumFeedPaneWidth, (available.width * 0.38).rounded(.down)))
        if usesMacToolbar || isPadSplit {
            assertClose(list.width, expectedFeedWidth, "Feed pane width in a \(available.width)-point area", line: line)
        }

        let card = post.frame.insetBy(dx: gutter, dy: 0)
        assertClose(card.width, list.width - 2 * gutter, "iPad feed card width", line: line)
        assertClose(card.minX - list.minX, gutter, "iPad feed card leading gutter", line: line)
        assertClose(list.maxX - card.maxX, gutter, "iPad feed card trailing gutter", line: line)
        assertFilterBarAligns(with: card, in: app, line: line)

        let placeholder = ForumFixture.element("feed-detail-placeholder", in: app)
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5), line: line)
        XCTAssertGreaterThanOrEqual(placeholder.frame.minX, list.maxX - tolerance,
                                    "The detail placeholder should sit beside the feed column.", line: line)
    }

    private func assertFilterBarAligns(with card: CGRect, in app: XCUIApplication, line: UInt = #line) {
        let category = app.buttons["选择版块，当前全部"]
        let newPost = app.buttons["发布帖子"]
        XCTAssertTrue(newPost.exists, line: line)
        if usesMacToolbar {
            // New post heads the sidebar beside the feed (or the toolbar above it once the sidebar folds away),
            // and the category menu sits in the toolbar, so neither lines up with the cards.
            XCTAssertTrue(newPost.frame.maxX <= card.minX + tolerance || newPost.frame.maxY <= card.minY + tolerance,
                          "The new post button should sit in the sidebar or toolbar, clear of the feed cards.", line: line)
            return
        }
        XCTAssertTrue(category.exists, line: line)
        assertClose(category.frame.minX, card.minX, "Category button and card leading edges", line: line)
        assertClose(newPost.frame.maxX, card.maxX, "New post button and card trailing edges", line: line)
    }

    private func feedListFrame(in app: XCUIApplication) -> CGRect {
        app.collectionViews
            .containing(NSPredicate(format: "label BEGINSWITH %@", ForumFixture.threadTitle)).firstMatch.frame
    }

    /// A card fills the width up to `readableWidth` and sits in the middle of the pane that scrolls it.
    private func assertColumn(_ card: CGRect, in page: CGRect, _ name: String, centred: Bool = true, line: UInt = #line) {
        if centred {
            let expectedWidth = min(readableWidth, page.width - 2 * gutter)
            assertClose(card.width, expectedWidth, "\(name) width in a \(page.width)-point page", line: line)
            assertClose(card.minX - page.minX, page.maxX - card.maxX, "\(name) side gaps", line: line)
        } else {
            XCTAssertLessThanOrEqual(card.width, readableWidth + tolerance, "\(name) keeps to the readable width.", line: line)
        }
    }

    /// Whether the tabs are currently shown in a sidebar beside the page.
    private func hasSidebar(_ app: XCUIApplication) -> Bool {
        sidebarTab(in: app).exists
    }

    private func sidebarTab(in app: XCUIApplication) -> XCUIElement {
        app.cells.matching(communityTab).firstMatch
    }

    private var communityTab: NSPredicate {
        NSPredicate(format: "elementType == %d AND label == %@", XCUIElement.ElementType.cell.rawValue, "社区")
    }

    /// The part of a page that a sidebar leaves free. The page runs on under the sidebar, but its cards
    /// centre or split in the area beside it.
    private func besideSidebar(_ page: CGRect, in app: XCUIApplication) -> CGRect {
        guard hasSidebar(app) else { return page }
        let sidebar = app.collectionViews.containing(communityTab).firstMatch.frame
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
