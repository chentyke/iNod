import Network
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

    private var server: NWListener?
    private var port: UInt16 {
        get throws { try XCTUnwrap(server?.port?.rawValue) }
    }

    override func setUp() async throws {
        continueAfterFailure = false
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        server = listener
        let ready = expectation(description: "Local website listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        let queue = DispatchQueue(label: "website-link-test")
        let html = """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>官网链接测试</title><p id="target"></p>
        <script>document.getElementById('target').textContent = new URL(location.href).searchParams.get('url') + ' / ' + location.port;</script>
        """
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 5)
    }

    override func tearDown() async throws {
        server?.cancel()
        browser.terminate()
    }

    func testViewOnWebsiteOpensTheBrowser() throws {
        let app = try ForumFixture.launchThread(extraArguments: ["-uiTestBrowserPort", String(port)])
        let more = app.buttons["更多"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let view = app.buttons["在官网查看"].firstMatch
        XCTAssertTrue(view.waitForExistence(timeout: 5))
        view.tap()

        try assertBrowserOpened("https://www.nodeseek.com/post-123-1", over: app)
    }

    func testWebsiteRowOnAccountOpensTheBrowser() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-offline", "-uiTestBrowserPort", try String(port)]
        app.launch()
        let account = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        let website = app.buttons["NodeSeek 官网"].firstMatch
        XCTAssertTrue(website.waitForExistence(timeout: 5))
        website.tap()

        try assertBrowserOpened("https://www.nodeseek.com/", over: app)
    }

    private func assertBrowserOpened(_ target: String, over app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        // The port distinguishes this page from a tab left by an earlier test run.
        let destination = try "\(target) / \(port)"
        let page = browser.webViews.staticTexts[destination].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 20), "Safari didn't show \(target)", file: file, line: line)
        app.activate()
        XCTAssertFalse(ForumFixture.title("NodeSeek 官网", in: app).exists, "The website opened inside the app", file: file, line: line)
    }
}
