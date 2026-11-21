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
    private func servePage(for target: String) throws -> (port: String, opened: XCTestExpectation) {
        continueAfterFailure = false
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        server = listener
        let ready = expectation(description: "Local website listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        let queue = DispatchQueue(label: "website-link-test")
        let opened = XCTestExpectation(description: "Safari received " + target)
        let html = """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>官网链接测试</title><p id="target"></p>
        <script>
        const target = new URL(location.href).searchParams.get('url');
        document.getElementById('target').textContent = target;
        </script>
        """
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.readHeaders(from: connection) { headers in
                let lines = headers.components(separatedBy: "\r\n")
                let requestTarget = lines.first?.split(separator: " ").dropFirst().first
                let url = requestTarget.flatMap { URLComponents(string: String($0)) }?
                    .queryItems?.first { $0.name == "url" }?.value
                let fromSafari = lines.contains { $0.lowercased().hasPrefix("user-agent:") && $0.contains("Safari/") }
                if url == target && fromSafari { opened.fulfill() }
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 5)
        // Let Safari finish its first launch before iNod hands it a link.
        browser.launch()
        return (String(try XCTUnwrap(listener.port?.rawValue)), opened)
    }

    // TCP can deliver the request line and Safari's User-Agent in different reads.
    private nonisolated static func readHeaders(from connection: NWConnection, buffer: Data = Data(),
                                                completion: @escaping @Sendable (String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { chunk, _, finished, error in
            guard let chunk, !chunk.isEmpty, error == nil else { connection.cancel(); return }
            let data = buffer + chunk
            if let end = data.range(of: Data("\r\n\r\n".utf8)) {
                completion(String(decoding: data[..<end.lowerBound], as: UTF8.self))
            } else if !finished && data.count < 16384 {
                readHeaders(from: connection, buffer: data, completion: completion)
            } else {
                connection.cancel()
            }
        }
    }

    override func tearDown() async throws {
        server?.cancel()
        browser.terminate()
    }

    func testViewOnWebsiteOpensTheBrowser() throws {
        let page = try servePage(for: "https://www.nodeseek.com/post-123-1")
        let app = ForumFixture.launchThread(extraArguments: ["-uiTestBrowserPort", page.port])
        let more = app.buttons["更多"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let view = app.buttons["在官网查看"].firstMatch
        XCTAssertTrue(view.waitForExistence(timeout: 5))
        view.tap()

        assertBrowserOpened(page.opened, over: app)
    }

    func testWebsiteRowOnAccountOpensTheBrowser() throws {
        let page = try servePage(for: "https://www.nodeseek.com/")
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-offline", "-uiTestBrowserPort", page.port]
        app.launch()
        let account = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        let website = app.buttons["NodeSeek 官网"].firstMatch
        XCTAssertTrue(website.waitForExistence(timeout: 5))
        website.tap()

        assertBrowserOpened(page.opened, over: app)
    }

    private func assertBrowserOpened(_ opened: XCTestExpectation, over app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        // The server saw Safari request the exact target passed by iNod.
        wait(for: [opened], timeout: 30)
        app.activate()
        XCTAssertFalse(ForumFixture.title("NodeSeek 官网", in: app).exists, "The website opened inside the app", file: file, line: line)
    }
}
