import XCTest

/// Checks the parts of docs/DESIGN.md that a running app can measure: corner controls sit as far from
/// the card's side as from its bottom (rule 6), and transient states close on an outside tap or a scroll
/// without swallowing taps inside them (rule 8).
@MainActor
final class DesignChecklistTests: XCTestCase {
    /// docs/DESIGN.md allows 2 points between gaps that should match.
    private let tolerance: CGFloat = 2

    override func setUp() {
        continueAfterFailure = false
    }

    func testReplyDockKeepsEvenGapsToTheCardEdges() throws {
        let app = launchThread()
        let card = app.otherElements["comment-2"]
        let dock = foldedDock(in: card)
        XCTAssertTrue(dock.waitForExistence(timeout: 5))

        assertEven(side: card.frame.maxX - dock.frame.maxX, bottom: card.frame.maxY - dock.frame.maxY, "Folded dock")

        dock.tap()
        // Signed out, nothing goes past a quote, so the quote button ends the opened dock.
        let last = card.buttons["引用回复"]
        XCTAssertTrue(last.waitForExistence(timeout: 3))
        // Let the opening spring settle before measuring.
        XCTAssertTrue(last.wait(for: \.isHittable, toEqual: true, timeout: 3))
        Thread.sleep(forTimeInterval: 0.6)
        assertEven(side: card.frame.maxX - last.frame.maxX, bottom: card.frame.maxY - last.frame.maxY, "Opened dock")
        XCTAssertLessThanOrEqual(last.frame.maxY, card.frame.maxY, "The opened dock stays inside its card.")
    }

    /// A reply with nothing to do but reply or quote shows the quote beside reply, with no ⋯ menu.
    func testOpenedDockShowsQuoteBesideReplyWhenNothingElseApplies() throws {
        let app = launchThread()
        let card = app.otherElements["comment-2"]
        XCTAssertTrue(foldedDock(in: card).waitForExistence(timeout: 5))

        foldedDock(in: card).tap()
        XCTAssertTrue(card.buttons["回复"].waitForExistence(timeout: 3))
        XCTAssertTrue(card.buttons["引用回复"].exists, "Quote should sit beside reply.")
        XCTAssertFalse(moreButton(in: card).exists, "With only a quote left, there is no ⋯ menu.")
    }

    /// When a reply can also be pinned or edited, ⋯ holds the quote and those actions, and never repeats reply.
    func testOpenedDockFoldsQuoteIntoMoreWhenOtherActionsApply() throws {
        // The thread's author can pin every reply.
        let app = ForumFixture.launchThread(signedInAsAuthor: true)
        let card = app.otherElements["comment-2"]
        XCTAssertTrue(foldedDock(in: card).waitForExistence(timeout: 5))

        foldedDock(in: card).tap()
        let more = moreButton(in: card)
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        XCTAssertTrue(card.buttons["回复"].exists)
        XCTAssertFalse(card.buttons["引用回复"].exists, "Quote moves into ⋯ when there is more to show.")

        XCTAssertTrue(more.wait(for: \.isHittable, toEqual: true, timeout: 3))
        more.tap()
        XCTAssertTrue(app.buttons["引用回复"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["置顶回复"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "回复")).count, 1,
                       "The ⋯ menu must not repeat the reply button beside it.")
    }

    func testOpenedDockFoldsOnOutsideTapScrollAndAnotherDock() throws {
        let app = launchThread()
        let first = app.otherElements["comment-2"]
        let second = app.otherElements["comment-3"]
        XCTAssertTrue(foldedDock(in: first).waitForExistence(timeout: 5))

        // A tap in the gap between cards folds it. Tap above the card: below it may sit under the reply bar.
        foldedDock(in: first).tap()
        XCTAssertTrue(first.buttons["回复"].waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: first.frame.midX, dy: first.frame.minY - 5)).tap()
        XCTAssertTrue(foldedDock(in: first).waitForExistence(timeout: 3), "A tap outside should fold the dock.")

        // Opening another dock folds the first, so only one is open.
        foldedDock(in: first).tap()
        XCTAssertTrue(first.buttons["回复"].waitForExistence(timeout: 3))
        foldedDock(in: second).tap()
        XCTAssertTrue(second.buttons["回复"].waitForExistence(timeout: 3))
        XCTAssertTrue(foldedDock(in: first).waitForExistence(timeout: 3), "Only one dock should be open at a time.")

        // A scroll folds it too.
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        XCTAssertTrue(app.buttons["回复"].waitForNonExistence(timeout: 3), "Scrolling should fold the dock.")
    }

    /// With a pointer, resting on a folded dock opens it, and resting on another one moves the opening there.
    ///
    /// Only the Mac runs it: the iPad simulator's synthesized hover never reaches the app's hover handlers,
    /// and on GitHub's Mac runner no input reaches the app, so it runs on a Mac at hand.
    func testPointerHoverOpensTheDock() throws {
        #if !targetEnvironment(macCatalyst)
        throw XCTSkip("Only the Mac delivers a test's pointer hover to the app.")
        #else
        let app = launchThread()
        let first = app.otherElements["comment-2"]
        let second = app.otherElements["comment-3"]
        XCTAssertTrue(foldedDock(in: first).waitForExistence(timeout: 5))

        foldedDock(in: first).hover()
        XCTAssertTrue(first.buttons["回复"].waitForExistence(timeout: 3), "Hovering over the folded dock should open it.")

        foldedDock(in: second).hover()
        XCTAssertTrue(second.buttons["回复"].waitForExistence(timeout: 3), "Hovering over another dock should open it.")
        XCTAssertTrue(foldedDock(in: first).waitForExistence(timeout: 3), "Only one dock should be open at a time.")
        #endif
    }

    func testFeedSearchFoldsOnScrollAndStaysFoldedAfterAPost() throws {
        let app = launchThread(opensPost: false)
        let open = app.buttons["搜索帖子"]
        let close = app.buttons["关闭搜索"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))

        open.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        // Drag in the top half: the software keyboard covers the bottom, and dragging on it scrolls nothing.
        drag(app, from: 0.5, to: 0.2)
        XCTAssertTrue(open.waitForExistence(timeout: 3), "Scrolling should fold an empty search.")

        drag(app, from: 0.3, to: 0.8)
        let card = ForumFixture.postCard(ForumFixture.announcementTitle, in: app)
        XCTAssertTrue(card.wait(for: \.isHittable, toEqual: true, timeout: 3))
        Thread.sleep(forTimeInterval: 1) // let the list stop, so the next tap is a tap
        open.tap()
        XCTAssertTrue(close.wait(for: \.isHittable, toEqual: true, timeout: 3))

        // Leaving for a post and coming back keeps the empty search folded and the keyboard down.
        card.tap()
        let back = app.buttons["返回"]
        XCTAssertTrue(back.wait(for: \.isHittable, toEqual: true, timeout: 5))
        back.tap()
        XCTAssertTrue(open.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertEqual(app.keyboards.count, 0, "Returning to the feed must not bring the keyboard back.")
    }

    // MARK: - Helpers

    /// Scrolls whatever list is on screen by dragging between two heights given as fractions of the screen.
    private func drag(_ app: XCUIApplication, from start: CGFloat, to end: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
            .press(forDuration: 0, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end)))
    }

    /// The Mac reports the menu button as a pop-up button rather than a button.
    private func moreButton(in card: XCUIElement) -> XCUIElement {
        card.descendants(matching: .any)["更多回复操作"]
    }

    private func foldedDock(in card: XCUIElement) -> XCUIElement {
        card.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "回复操作")).firstMatch
    }

    private func assertEven(side: CGFloat, bottom: CGFloat, _ name: String, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(side - bottom), tolerance,
                                 "\(name): side gap \(side) and bottom gap \(bottom) should match.", line: line)
    }

    private func launchThread(opensPost: Bool = true) -> XCUIApplication {
        opensPost ? ForumFixture.launchThread() : ForumFixture.launch()
    }
}
