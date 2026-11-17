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

    func testWideTableScrollsAndKeepsColumnsAfterAnEmptyCell() {
        continueAfterFailure = false
        let headings = (1...11).map { "第\($0)列" }.joined(separator: " | ")
        let rule = Array(repeating: "---", count: 11).joined(separator: " | ")
        let cells = (["开头", "", "空格之后"] + (4...10).map { "内容\($0)" } + ["最后一格"])
            .joined(separator: " | ")
        let app = ForumFixture.launch(dark: true, opensThread: true, openingMarkdown: """
        | \(headings) |
        | \(rule) |
        | \(cells) |
        """)

        let table = app.scrollViews["markdown-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 8))

        let thirdHeading = app.staticTexts["第3列"]
        let thirdCell = app.staticTexts["空格之后"]
        let lastCell = app.staticTexts["最后一格"]
        XCTAssertTrue(thirdHeading.exists)
        XCTAssertTrue(thirdCell.exists)
        XCTAssertEqual(thirdHeading.frame.minX, thirdCell.frame.minX, accuracy: 1)
        XCTAssertFalse(lastCell.isHittable)

        for _ in 0..<4 {
            if lastCell.isHittable { break }
            table.swipeLeft()
        }
        XCTAssertTrue(lastCell.isHittable)
    }
}
