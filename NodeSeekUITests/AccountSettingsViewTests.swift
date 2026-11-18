import XCTest

@MainActor
final class AccountSettingsViewTests: XCTestCase {
    private let readableWidth = 760 * ForumFixture.pointScale
    private let gutter = 16 * ForumFixture.pointScale
    private let tolerance: CGFloat = 2

    override func setUp() {
        continueAfterFailure = false
    }

    func testAccountSettingsDisplaysIdentityGroupsAndNavigatesSubpages() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchAccountSettings()
        XCTAssertTrue(ForumFixture.title("账号设置", in: app).waitForExistence(timeout: 5))

        let identityCard = ForumFixture.element("account-settings-identity-card", in: app)
        XCTAssertTrue(identityCard.waitForExistence(timeout: 5))
        XCTAssertTrue(identityCard.label.contains("测试用户"))
        XCTAssertTrue(identityCard.label.contains("UID 9900315"), "UID should not contain thousand separators.")
        XCTAssertFalse(identityCard.label.contains("9,900,315"))
        XCTAssertTrue(identityCard.label.contains("Lv 3"))

        assertReadableColumn(in: app, elementIdentifier: "account-settings-identity-card")
        attachScreenshot(of: app, named: "account-settings-after-light")

        // 1. Profile Editor
        tapRow("settings-row-profile", in: app)
        XCTAssertTrue(ForumFixture.title("编辑资料", in: app).waitForExistence(timeout: 5))
        let modePicker = ForumFixture.element("profile-editor-mode-picker", in: app)
        XCTAssertTrue(modePicker.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "profile-editor-after-light")
        modePicker.buttons["预览"].tap()
        XCTAssertTrue(app.staticTexts["热爱开源与网络技术"].waitForExistence(timeout: 5))
        popBack(to: "账号设置", in: app)

        // 2. Avatar Editor
        tapRow("settings-row-avatar", in: app)
        XCTAssertTrue(ForumFixture.title("修改头像", in: app).waitForExistence(timeout: 5))
        let avatarPreview = ForumFixture.element("avatar-editor-preview", in: app)
        XCTAssertTrue(avatarPreview.waitForExistence(timeout: 5))
        XCTAssertTrue(avatarPreview.label.contains("当前头像"))
        XCTAssertTrue(ForumFixture.element("avatar-pick-button", in: app).exists)
        attachScreenshot(of: app, named: "avatar-editor-after-light")
        popBack(to: "账号设置", in: app)

        // 3. Homepage Settings
        tapRow("settings-row-homepage", in: app)
        XCTAssertTrue(ForumFixture.title("首页版块", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["技术"].waitForExistence(timeout: 5))
        let saveHomepage = ForumFixture.element("homepage-save-button", in: app)
        XCTAssertFalse(saveHomepage.isEnabled)
        let tradeToggle = app.switches.matching(identifier: "homepage-category-trade").firstMatch
        XCTAssertTrue(tradeToggle.waitForExistence(timeout: 5))
        tradeToggle.switches.firstMatch.tap()
        if !saveHomepage.isEnabled {
            tradeToggle.tap()
        }
        XCTAssertTrue(saveHomepage.isEnabled)
        saveHomepage.tap()
        XCTAssertTrue(app.staticTexts["首页版块设置已同步到 NodeSeek。"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "homepage-settings-after-light")
        popBack(to: "账号设置", in: app)

        // 4. Blocked Members
        tapRow("settings-row-blocks", in: app)
        XCTAssertTrue(ForumFixture.title("屏蔽用户", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["广告账号"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UID 9900088"].exists)
        attachScreenshot(of: app, named: "blocked-members-after-light")
        let unblockButton = ForumFixture.element("unblock-member-9900088", in: app)
        XCTAssertTrue(unblockButton.waitForExistence(timeout: 5))
        unblockButton.tap()
        let unblockAlert = app.alerts["解除对「广告账号」的屏蔽？"]
        XCTAssertTrue(unblockAlert.waitForExistence(timeout: 5))
        unblockAlert.buttons["取消"].tap()
        popBack(to: "账号设置", in: app)

        // 5. Website Preferences
        tapRow("settings-row-website-preferences", in: app)
        XCTAssertTrue(ForumFixture.title("官网显示设置", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(ForumFixture.element("website-css-editor", in: app).waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "website-preferences-after-light")
        popBack(to: "账号设置", in: app)

        // 6. Sign Out Confirmation
        tapRow("settings-sign-out-button", in: app)
        let signOutAlert = app.alerts["退出登录？"]
        XCTAssertTrue(signOutAlert.waitForExistence(timeout: 5))
        signOutAlert.buttons["取消"].tap()
        XCTAssertTrue(ForumFixture.title("账号设置", in: app).exists)
        #endif
    }

    func testAccountSecurityAndVerificationSubpages() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchAccountSettings()
        tapRow("settings-row-security", in: app)
        XCTAssertTrue(ForumFixture.title("登录与安全", in: app).waitForExistence(timeout: 5))

        let twoFactorRow = ForumFixture.element("security-row-2fa", in: app)
        XCTAssertTrue(twoFactorRow.waitForExistence(timeout: 5))
        XCTAssertTrue(twoFactorRow.label.contains("已开启"))
        XCTAssertTrue(app.staticTexts["203.0.113.42"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["最近一次"].exists)
        assertReadableColumn(in: app, elementIdentifier: "security-row-password")
        attachScreenshot(of: app, named: "account-security-after-light")

        // 1. Password View
        tapRow("security-row-password", in: app)
        XCTAssertTrue(ForumFixture.title("修改密码", in: app).waitForExistence(timeout: 5))
        let savePassword = ForumFixture.element("password-save-button", in: app)
        XCTAssertTrue(savePassword.waitForExistence(timeout: 5))
        XCTAssertFalse(savePassword.isEnabled)
        let newPasswordField = ForumFixture.element("password-new-field", in: app)
        newPasswordField.tap()
        newPasswordField.typeText("abc")
        XCTAssertTrue(app.staticTexts["新密码长度需为 6–18 位（当前 3 位）。"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "password-view-after-light")
        popBack(to: "登录与安全", in: app)

        // 2. Two-Factor View
        tapRow("security-row-2fa", in: app)
        XCTAssertTrue(ForumFixture.title("双因素验证", in: app).waitForExistence(timeout: 5))
        let statusCard = ForumFixture.element("two-factor-status-card", in: app)
        XCTAssertTrue(statusCard.waitForExistence(timeout: 5))
        XCTAssertTrue(statusCard.label.contains("双因素验证已开启"))
        XCTAssertFalse(ForumFixture.element("two-factor-action-button", in: app).isEnabled)
        attachScreenshot(of: app, named: "two-factor-after-light")
        popBack(to: "登录与安全", in: app)

        // 3. Telegram Settings View
        tapRow("security-row-telegram", in: app)
        XCTAssertTrue(ForumFixture.title("Telegram 提醒", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已绑定 Telegram"].waitForExistence(timeout: 5))
        let telegramUsername = ForumFixture.element("telegram-username-row", in: app)
        XCTAssertTrue(telegramUsername.waitForExistence(timeout: 5))
        XCTAssertTrue(telegramUsername.label.contains("@nodeseek_reader"))
        attachScreenshot(of: app, named: "telegram-settings-after-light")
        let unbindButton = ForumFixture.element("telegram-unbind-button", in: app)
        XCTAssertTrue(unbindButton.waitForExistence(timeout: 5))
        for _ in 0..<3 where !unbindButton.isHittable { app.swipeUp() }
        unbindButton.tap()
        let unbindAlert = app.alerts["解除 Telegram 绑定？"]
        XCTAssertTrue(unbindAlert.waitForExistence(timeout: 5))
        unbindAlert.buttons["取消"].tap()
        #endif
    }

    func testDarkModeRendersAccountSettingsAndSecurity() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Mac Catalyst UI tests cannot click into app content.")
        #else
        let app = try launchAccountSettings(dark: true)
        XCTAssertTrue(ForumFixture.element("account-settings-identity-card", in: app).waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "account-settings-after-dark")

        tapRow("settings-row-security", in: app)
        XCTAssertTrue(ForumFixture.title("登录与安全", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["203.0.113.42"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "account-security-after-dark")
        #endif
    }

    private func tapRow(_ identifier: String, in app: XCUIApplication, line: UInt = #line) {
        let row = ForumFixture.element(identifier, in: app)
        if !row.waitForExistence(timeout: 3) {
            for _ in 0..<4 where !row.exists { app.swipeUp() }
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing row \(identifier)", line: line)
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        row.tap()
    }

    private func popBack(to expectedTitle: String, in app: XCUIApplication, line: UInt = #line) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(ForumFixture.title(expectedTitle, in: app).waitForExistence(timeout: 5), line: line)
    }

    private func assertReadableColumn(in app: XCUIApplication, elementIdentifier: String, line: UInt = #line) {
        let list = app.collectionViews.containing(.any, identifier: elementIdentifier).firstMatch
        let cell = list.cells.containing(.any, identifier: elementIdentifier).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), line: line)
        let listFrame = list.frame
        let rowFrame = cell.frame
        XCTAssertLessThanOrEqual(rowFrame.width, readableWidth + tolerance, "Settings card keeps to readable width.", line: line)
        let expectedSideGap = max(gutter, ((listFrame.width - readableWidth) / 2).rounded(.down))
        XCTAssertLessThanOrEqual(abs((rowFrame.minX - listFrame.minX) - expectedSideGap), tolerance, line: line)
        XCTAssertLessThanOrEqual(abs((listFrame.maxX - rowFrame.maxX) - expectedSideGap), tolerance, line: line)
    }

    private func launchAccountSettings(dark: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [], "pinnedPosts": [], "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "/api/account/getInfo/9900315?readme=1&signature=1": [
                "id": 9_900_315,
                "name": "测试用户",
                "bio": "热爱开源与网络技术",
                "signature": "保持简洁，持续构建。",
                "readme": "欢迎来到我的主页。\n\n- 关注 iOS 与网络工具\n- 记录折腾笔记",
                "coins": 1280,
                "stardust": 155,
                "topics": 12,
                "replies": 86,
                "follows": 15,
                "fans": 29
            ],
            "/api/homepage": [
                "items": [
                    ["id": "daily", "title": "日常", "enabled": true],
                    ["id": "tech", "title": "技术", "enabled": true],
                    ["id": "trade", "title": "交易", "enabled": false]
                ],
                "hasNext": false
            ],
            "POST /api/homepage": ["success": true],
            "/api/block-list/list": [
                "items": [
                    ["id": 9_900_088, "name": "广告账号"],
                    ["id": 9_900_099, "name": "刷屏机器人"]
                ],
                "hasNext": false
            ],
            "/api/account/otp-status": [
                "enabled": true,
                "twoFactorEnabled": true,
                "history": [
                    ["id": "0-1794900000", "ip": "203.0.113.42", "createdAt": "2026-11-18T02:15:00.000Z"],
                    ["id": "1-1794800000", "ip": "198.51.100.18", "createdAt": "2026-11-16T19:40:00.000Z"]
                ]
            ],
            "https://www.nodeseek.com/setting": [
                "userID": 9_900_315,
                "bound": true
            ],
            "/api/account/telegram": [
                "telegramDetail": [
                    "first_name": "NodeSeek",
                    "last_name": "Reader",
                    "username": "nodeseek_reader"
                ]
            ],
            "POST /api/preference/list": [
                "data": ["enable_festivous_style": true]
            ],
            "/api/style": [
                "data": "/* 自定义阅读行高 */\n.post-content { line-height: 1.75; }"
            ]
        ]
        let encodedResponses = try responses.mapValues {
            try JSONSerialization.data(withJSONObject: $0).base64EncodedString()
        }
        let fixture: [String: Any] = [
            "authentication": [
                "ready": true,
                "user": [
                    "id": 9_900_315,
                    "name": "测试用户",
                    "coins": 1280,
                    "stardust": 155,
                    "canCustomizeStyle": true
                ]
            ],
            "responses": encodedResponses
        ]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] =
            String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchArguments += ["-appearance", dark ? "dark" : "light"]
        app.launch()

        let myTab = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(myTab.waitForExistence(timeout: 8))
        myTab.tap()

        let settings = app.buttons["账号设置"].firstMatch
        for _ in 0..<4 where !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(ForumFixture.title("账号设置", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(ForumFixture.element("account-settings-identity-card", in: app).waitForExistence(timeout: 5))
        return app
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
