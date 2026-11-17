import XCTest

@MainActor
final class MarkdownTableTests: XCTestCase {
    func testUnevenRowsStayAlignedWithWidestRowLast() {
        continueAfterFailure = false
        let app = ForumFixture.launch(opensThread: true, openingMarkdown: """
        | 书名 | 进度 |
        | --- | --- |
        | 简爱 |
        | 小王子 | 已读完 | 可借阅 |
        """)

        let title = app.staticTexts["书名"]
        let status = app.staticTexts["进度"]
        let shortRow = app.staticTexts["简爱"]
        let lastTitle = app.staticTexts["小王子"]
        let lastStatus = app.staticTexts["已读完"]
        let extraCell = app.staticTexts["可借阅"]

        XCTAssertTrue(extraCell.waitForExistence(timeout: 8))
        XCTAssertTrue(title.exists)
        XCTAssertTrue(status.exists)
        XCTAssertTrue(shortRow.exists)
        XCTAssertTrue(lastTitle.exists)
        XCTAssertTrue(lastStatus.exists)

        XCTAssertLessThan(title.frame.midY, shortRow.frame.midY)
        XCTAssertLessThan(shortRow.frame.midY, lastTitle.frame.midY)
        XCTAssertEqual(title.frame.minX, shortRow.frame.minX, accuracy: 1)
        XCTAssertEqual(title.frame.minX, lastTitle.frame.minX, accuracy: 1)
        XCTAssertEqual(status.frame.minX, lastStatus.frame.minX, accuracy: 1)
        XCTAssertEqual(lastTitle.frame.midY, extraCell.frame.midY, accuracy: 1)
        XCTAssertLessThan(lastStatus.frame.maxX, extraCell.frame.minX)
    }
}
