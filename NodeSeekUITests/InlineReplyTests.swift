import XCTest

#if !targetEnvironment(macCatalyst)
@MainActor
final class InlineReplyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testPadQuotedDraftStaysInTheThreadColumnThroughRotation() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires an iPad.")
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let quote = "@读者 [#2](https://www.nodeseek.com/post-123-1#2) \n\n> 周六下午两点开始读书。\n\n"
        let image = "\n![图片](<https://example.invalid/reading.jpg>)\n"
        let app = ForumFixture.launch(opensThread: true, signedInAsAuthor: true,
                                      authorID: Int.random(in: 1_000_000...2_000_000), replyDraft: quote + image)
        let write = app.buttons["写回复"]
        XCTAssertTrue(write.wait(for: \.isEnabled, toEqual: true, timeout: 10))
        write.tap()
        let body = ForumFixture.element("回复正文", in: app)
        let send = app.buttons["发送回复"]
        let removeImage = app.buttons["移除第 1 张图片"]
        let removeQuote = app.buttons["移除引用"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.typeText("Saturday")

        for orientation: UIDeviceOrientation in [.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(send.wait(for: \.isHittable, toEqual: true, timeout: 5))
            XCTAssertEqual(body.value as? String, "Saturday")
            XCTAssertTrue(removeQuote.exists && removeImage.exists)
            let card = ForumFixture.element("comment-1", in: app)
            XCTAssertTrue(card.exists)
            XCTAssertGreaterThanOrEqual(body.frame.minX, card.frame.minX)
            XCTAssertLessThanOrEqual(send.frame.maxX, card.frame.maxX)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists { XCTAssertLessThanOrEqual(send.frame.maxY, keyboard.frame.minY + 2) }
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = orientation == .portrait ? "iPad portrait reply" : "iPad landscape reply"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        app.buttons["完整编辑"].tap()
        let editor = app.textViews["正文，支持 Markdown"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(editor.frame.height, 64)
        XCTAssertEqual(editor.value as? String, "Saturday")
        let quoteHeader = ForumFixture.element("full-reply-quote", in: app)
        XCTAssertGreaterThan(quoteHeader.frame.minX, editor.frame.maxX)
        let editorShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editorShot.name = "iPad landscape full editor"
        editorShot.lifetime = .keepAlways
        add(editorShot)

        app.buttons["预览"].tap()
        let preview = ForumFixture.element("reply-preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(preview.frame.minX, editor.frame.maxX)
        editor.typeText(" meeting\n\n- Notebook\n- Pencil")
        let renderedText = preview.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Saturday meeting")).firstMatch
        XCTAssertTrue(renderedText.waitForExistence(timeout: 5))
        let previewShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        previewShot.name = "iPad live Markdown preview"
        previewShot.lifetime = .keepAlways
        add(previewShot)
        app.buttons["收起预览"].tap()
        app.buttons["稍后再写"].tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue(removeQuote.exists && removeImage.exists)
        let nextPost = ForumFixture.postCard(ForumFixture.announcementTitle, in: app)
        XCTAssertTrue(nextPost.isHittable)
        nextPost.tap()
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        XCTAssertFalse(removeQuote.exists)
        XCTAssertNotEqual(write.value as? String, "Saturday meeting\n\n- Notebook\n- Pencil")
        ForumFixture.postCard(ForumFixture.threadTitle, in: app).tap()
        XCTAssertTrue(write.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        write.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "Saturday meeting\n\n- Notebook\n- Pencil")
        XCTAssertTrue(removeQuote.exists && removeImage.exists)
    }

    func testQuickReplyKeepsTextThroughFullEditorAndClearsItAfterSending() {
        let response = Data(#"{"success":true}"#.utf8)
        let app = ForumFixture.launch(opensThread: true, signedInAsAuthor: true,
                                      authorID: Int.random(in: 1_000_000...2_000_000),
                                      assetResponses: ["POST /api/content/new-comment": response])
        let write = app.buttons["写回复"]
        XCTAssertTrue(write.wait(for: \.isEnabled, toEqual: true, timeout: 10))
        write.tap()
        let body = ForumFixture.element("回复正文", in: app)
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let send = app.buttons["发送回复"]
        XCTAssertFalse(send.isEnabled)
        body.typeText("See you on Saturday!")
        XCTAssertTrue(send.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Inline reply on thread"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["完整编辑"].tap()
        let editor = app.textViews["正文，支持 Markdown"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "See you on Saturday!")
        editor.typeText(" OK")
        let fullEditor = XCTAttachment(screenshot: app.screenshot())
        fullEditor.name = "Full reply editor"
        fullEditor.lifetime = .keepAlways
        add(fullEditor)
        app.buttons["稍后再写"].tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue((body.value as? String)?.contains(" OK") == true)
        send.tap()
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        XCTAssertTrue(send.waitForExistence(timeout: 3))
        XCTAssertFalse(send.isEnabled)
    }

    func testQuickReplyCanOpenPhotosAndKeepItsDraftAfterCancellation() {
        let app = ForumFixture.launch(opensThread: true, signedInAsAuthor: true,
                                      authorID: Int.random(in: 1_000_000...2_000_000))
        let write = app.buttons["写回复"]
        XCTAssertTrue(write.wait(for: \.isEnabled, toEqual: true, timeout: 10))
        write.tap()
        let body = ForumFixture.element("回复正文", in: app)
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.typeText("Weekend")
        app.buttons["选择图片"].tap()
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "取消", "Close", "Cancel"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 8))
        XCTAssertEqual(body.value as? String, "Weekend")
        XCTAssertTrue(app.buttons["发送回复"].isEnabled)
    }

    func testImageOnlyDraftKeepsPhotosAcrossEditorsAndCanBeSent() {
        // Start with the same saved draft that two successful uploads produce.
        let images = ["first", "second"].map { "\n![图片](<https://example.invalid/\($0).jpg>)\n" }.joined()
        let app = ForumFixture.launch(opensThread: true, signedInAsAuthor: true,
                                      authorID: Int.random(in: 1_000_000...2_000_000),
                                      assetResponses: ["POST /api/content/new-comment": Data(#"{"success":true}"#.utf8)],
                                      replyDraft: images)
        let write = app.buttons["写回复"]
        XCTAssertTrue(write.wait(for: \.isEnabled, toEqual: true, timeout: 10))
        write.tap()
        let expand = app.buttons["完整编辑"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        let second = app.buttons["移除第 2 张图片"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.tap()
        XCTAssertTrue(second.waitForNonExistence(timeout: 3))
        expand.tap()
        XCTAssertTrue(app.buttons["移除第 1 张图片"].waitForExistence(timeout: 5))
        XCTAssertFalse(second.exists)
        app.buttons["稍后再写"].tap()
        let send = app.buttons["发送回复"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(write.waitForExistence(timeout: 5))
    }

    func testOutsideTapsCloseTheReplyAndLeaveControlsUsable() {
        let app = ForumFixture.launch(opensThread: true, signedInAsAuthor: true,
                                      authorID: Int.random(in: 1_000_000...2_000_000))
        let write = app.buttons["写回复"]
        let expand = app.buttons["完整编辑"]
        let send = app.buttons["发送回复"]
        let body = ForumFixture.element("回复正文", in: app)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func openReply() {
            XCTAssertTrue(write.wait(for: \.isHittable, toEqual: true, timeout: 8))
            write.tap()
            XCTAssertTrue(expand.waitForExistence(timeout: 5))
        }

        openReply()
        XCTAssertEqual(send.frame.minX - expand.frame.maxX, 4, accuracy: 2)
        body.tap()
        body.typeText("Keep this draft")
        XCTAssertTrue(send.isEnabled)
        // The margin beside the glass is outside the reply, even at the height of its buttons.
        origin.withOffset(CGVector(dx: app.frame.maxX - 5, dy: expand.frame.midY)).tap()
        openReply()
        XCTAssertEqual(body.value as? String, "Keep this draft")
        ForumFixture.threadText("周六下午两点开始读书。", in: app).tap()
        openReply()
        let discussion = app.staticTexts["讨论"].firstMatch
        origin.withOffset(CGVector(dx: discussion.frame.midX, dy: discussion.frame.minY - 5)).tap()
        openReply()
        app.buttons["更多"].firstMatch.tap()
        XCTAssertTrue(app.buttons["在官网查看"].waitForExistence(timeout: 4))
        XCTAssertTrue(expand.waitForNonExistence(timeout: 3))
    }

    func testQuoteOpensInlineAndCanBeRemovedWithoutLosingTheAnswer() {
        let app = ForumFixture.launch(opensThread: true, signedInAsAuthor: true,
                                      authorID: Int.random(in: 1_000_000...2_000_000))
        let card = ForumFixture.element("comment-2", in: app)
        let dock = card.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "回复操作")).firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        dock.tap()
        let more = card.descendants(matching: .any)["更多回复操作"]
        XCTAssertTrue(more.wait(for: \.isHittable, toEqual: true, timeout: 4))
        more.tap()
        let quote = ForumFixture.element("引用回复", in: app)
        XCTAssertTrue(quote.waitForExistence(timeout: 4))
        quote.tap()

        let body = ForumFixture.element("回复正文", in: app)
        let remove = app.buttons["移除引用"]
        let send = app.buttons["发送回复"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertTrue(body.exists)
        XCTAssertFalse(send.isEnabled)
        body.typeText("See you there!")
        XCTAssertTrue(send.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Inline quoted reply"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.staticTexts[ForumFixture.threadTitle].firstMatch.tap()
        app.buttons["写回复"].tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "See you there!")
        app.buttons["完整编辑"].tap()
        let editor = app.textViews["正文，支持 Markdown"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "See you there!")
        let editorQuote = ForumFixture.element("full-reply-quote", in: app)
        XCTAssertTrue(editorQuote.buttons["移除引用"].exists)
        app.buttons["预览"].tap()
        let closePreview = app.buttons.matching(NSPredicate(format: "label IN %@", ["继续撰写", "收起预览"])).firstMatch
        XCTAssertTrue(closePreview.waitForExistence(timeout: 5))
        closePreview.tap()
        editorQuote.buttons["移除引用"].tap()
        app.buttons["稍后再写"].tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertFalse(remove.exists)
        XCTAssertEqual(body.value as? String, "See you there!")
        XCTAssertTrue(send.isEnabled)
    }

    func testReplyToFloorKeepsRecipientSeparateFromText() {
        let response = Data(#"{"success":false,"message":"请稍后再试"}"#.utf8)
        let app = ForumFixture.launch(dark: true, opensThread: true, signedInAsAuthor: true,
                                      authorID: Int.random(in: 1_000_000...2_000_000),
                                      assetResponses: ["POST /api/content/new-comment": response])
        let card = ForumFixture.element("comment-2", in: app)
        let dock = card.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "回复操作")).firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        dock.tap()
        let reply = card.buttons["回复"]
        XCTAssertTrue(reply.waitForExistence(timeout: 3))
        reply.tap()
        let body = ForumFixture.element("回复正文", in: app)
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let target = app.buttons["取消回复此楼"]
        XCTAssertTrue(target.exists)
        body.typeText("Thanks!")
        app.staticTexts[ForumFixture.threadTitle].firstMatch.tap()
        let write = app.buttons["写回复"]
        XCTAssertTrue(write.waitForExistence(timeout: 3))
        write.tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "Thanks!")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reply to floor in dark mode"
        attachment.lifetime = .keepAlways
        add(attachment)
        target.tap()
        XCTAssertFalse(target.exists)
        app.buttons["发送回复"].tap()
        XCTAssertTrue(app.alerts["回复未完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["请稍后再试"].exists)
        app.buttons["好"].tap()
        XCTAssertEqual(body.value as? String, "Thanks!")
    }
}
#endif
