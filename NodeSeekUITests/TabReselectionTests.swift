import UIKit
import XCTest

#if !targetEnvironment(macCatalyst)
@MainActor
final class TabReselectionTests: XCTestCase {
    func testCommunityReselectionScrollsTheFeedToTop() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Tests the iPhone tab bar") }
        continueAfterFailure = false
        let app = ForumFixture.launch()
        let community = ForumFixture.tab("社区", in: app)
        let account = ForumFixture.tab("我的", in: app)
        let firstPost = ForumFixture.postCard(ForumFixture.threadTitle, in: app)
        XCTAssertTrue(firstPost.waitForExistence(timeout: 10))
        let top = firstPost.frame.minY

        app.swipeUp()
        XCTAssertFalse(firstPost.isHittable)
        account.tap()
        community.tap()
        XCTAssertFalse(firstPost.isHittable, "Switching tabs should keep the feed's scroll position")

        community.tap()
        XCTAssertTrue(firstPost.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertEqual(firstPost.frame.minY, top, accuracy: 1)
        recordScreen("社区重按标签后")

        app.swipeUp()
        XCTAssertFalse(firstPost.isHittable)
        community.tap()
        XCTAssertTrue(firstPost.wait(for: \.isHittable, toEqual: true, timeout: 5))
    }

    private func recordScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
