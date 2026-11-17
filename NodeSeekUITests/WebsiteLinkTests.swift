import XCTest

/// "在官网查看" and the other website rows open the reader's browser, not a page inside the app.
@MainActor
final class WebsiteLinkTests: XCTestCase {
    private let browser: XCUIApplication = {
        #if targetEnvironment(macCatalyst)
        XCUIApplication(bundleIdentifier: "com.apple.Safari")
        #else
        XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        #endif
    }()

    override func setUp() {
        continueAfterFailure = false
        browser.terminate()
    }

    override func tearDown() { browser.terminate() }

    func testViewOnWebsiteOpensTheBrowser() {
        let app = ForumFixture.launchThread()
        let more = app.buttons["更多"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let view = app.buttons["在官网查看"].firstMatch
        XCTAssertTrue(view.waitForExistence(timeout: 5))
        view.tap()

        assertBrowserOpened(over: app)
    }

    func testWebsiteRowOnAccountOpensTheBrowser() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-offline"]
        app.launch()
        let account = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        let website = app.buttons["NodeSeek 官网"].firstMatch
        XCTAssertTrue(website.waitForExistence(timeout: 5))
        website.tap()

        assertBrowserOpened(over: app)
    }

    private func assertBrowserOpened(over app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(browser.wait(for: .runningForeground, timeout: 15), "The browser didn't open", file: file, line: line)
        app.activate()
        XCTAssertFalse(ForumFixture.title("NodeSeek 官网", in: app).exists, "The website opened inside the app", file: file, line: line)
    }
}
