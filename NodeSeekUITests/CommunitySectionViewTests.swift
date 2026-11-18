import XCTest

#if !targetEnvironment(macCatalyst)
@MainActor
final class CommunitySectionViewTests: XCTestCase {
    private let tolerance: CGFloat = 2

    override func setUp() {
        continueAfterFailure = false
    }

    func testCommunitySectionAndAllSubpagesNavigateAndOperate() throws {
        let app = try launchCommunityTools(signedIn: true)

        let recommendedTile = ForumFixture.element("community-tile-recommended", in: app)
        let luckyTile = ForumFixture.element("community-tile-lucky", in: app)
        XCTAssertTrue(recommendedTile.waitForExistence(timeout: 5))
        XCTAssertTrue(luckyTile.exists)

        // Featured tiles sit side-by-side with equal width, matching top edge, and a 12pt gap.
        XCTAssertLessThanOrEqual(abs(recommendedTile.frame.width - luckyTile.frame.width), tolerance)
        XCTAssertLessThanOrEqual(abs(recommendedTile.frame.minY - luckyTile.frame.minY), tolerance)
        XCTAssertLessThanOrEqual(
            abs((luckyTile.frame.minX - recommendedTile.frame.maxX) - 12 * ForumFixture.pointScale),
            tolerance
        )
        assertReadableColumn(in: app, elementIdentifier: "community-featured-tiles")
        attachScreenshot(of: app, named: "after-community-tools-light")

        // 1. Recommended Reading (no non-functional category/sort/new-post bar)
        recommendedTile.tap()
        XCTAssertTrue(ForumFixture.title("推荐阅读", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["林风"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["发布帖子"].exists)
        attachScreenshot(of: app, named: "after-recommended-light")
        popBack(to: "社区工具", in: app)

        // 2. Member Search (direct UID jump + @username lookup while keeping back button visible)
        tapRow("community-row-member-search", in: app)
        XCTAssertTrue(ForumFixture.title("查找用户", in: app).waitForExistence(timeout: 5))
        let memberField = ForumFixture.element("member-search-field", in: app)
        XCTAssertTrue(memberField.waitForExistence(timeout: 5))
        memberField.tap()
        memberField.typeText("9900101")
        XCTAssertTrue(ForumFixture.element("member-search-direct-9900101", in: app).waitForExistence(timeout: 5))

        ForumFixture.element("member-search-field-clear", in: app).tap()
        memberField.tap()
        memberField.typeText("@alice")
        ForumFixture.element("member-search-submit", in: app).tap()

        let aliceRow = ForumFixture.element("searched-member-9900101", in: app)
        XCTAssertTrue(aliceRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UID 9900101 · Lv 3"].exists)
        attachScreenshot(of: app, named: "after-member-search-light")
        popBack(to: "社区工具", in: app)

        // 3. Lucky Draw (labeled inputs, link import, deterministic drand reveal, winner rows)
        ForumFixture.element("community-tile-lucky", in: app).tap()
        XCTAssertTrue(ForumFixture.title("抽奖工具", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["中奖人数"].exists)
        XCTAssertTrue(app.staticTexts["起始楼层"].exists)
        attachScreenshot(of: app, named: "after-lucky-draw-form-light")

        let postField = ForumFixture.element("lucky-post-field", in: app)
        XCTAssertTrue(postField.waitForExistence(timeout: 5))
        postField.tap()
        postField.typeText("https://www.nodeseek.com/lucky?post=301&time=1700000000000&count=2&start=1&duplicate=false&mode=view")
        XCTAssertTrue(ForumFixture.element("lucky-apply-link-button", in: app).waitForExistence(timeout: 5))

        let revealButton = ForumFixture.element("lucky-reveal-button", in: app)
        for _ in 0..<3 where !(revealButton.exists && revealButton.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(revealButton.waitForExistence(timeout: 5))
        revealButton.tap()

        XCTAssertTrue(app.staticTexts["2 人中奖"].waitForExistence(timeout: 5))
        let copyWinners = ForumFixture.element("lucky-copy-winners", in: app)
        for _ in 0..<2 where !copyWinners.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(copyWinners.exists)
        attachScreenshot(of: app, named: "after-lucky-draw-light")
        popBack(to: "社区工具", in: app)

        // 4. Rulings List & Ruling Detail Subpage
        tapRow("community-row-rulings", in: app)
        XCTAssertTrue(ForumFixture.title("管理记录", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(ForumFixture.element("rulings-search-field", in: app).exists)
        let rulingRow = ForumFixture.element("ruling-row-801", in: app)
        XCTAssertTrue(rulingRow.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "after-rulings-light")

        rulingRow.tap()
        XCTAssertTrue(ForumFixture.title("记录详情", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(ForumFixture.element("rulings-search-field", in: app).exists)
        XCTAssertTrue(ForumFixture.element("ruling-detail-action-coin", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(ForumFixture.element("ruling-detail-target", in: app).exists)
        XCTAssertTrue(ForumFixture.element("ruling-detail-admin", in: app).exists)
        let detailPost = ForumFixture.element("ruling-detail-post", in: app)
        XCTAssertTrue(detailPost.exists)
        attachScreenshot(of: app, named: "after-ruling-detail-light")

        detailPost.tap()
        XCTAssertTrue(app.staticTexts["第 3 楼：感谢分享详细配置。"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(ForumFixture.title("记录详情", in: app).waitForExistence(timeout: 5))
        popBack(to: "管理记录", in: app)
        popBack(to: "社区工具", in: app)

        // 5. Invitations (balance/shortfall states, alert confirmation, fixed-size copy capsule)
        tapRow("community-row-invitations", in: app)
        XCTAssertTrue(ForumFixture.title("邀请朋友", in: app).waitForExistence(timeout: 5))
        let buyCoin = ForumFixture.element("invitation-buy-coin", in: app)
        let buyStardust = ForumFixture.element("invitation-buy-stardust", in: app)
        XCTAssertTrue(buyCoin.waitForExistence(timeout: 5))
        XCTAssertTrue(buyCoin.isEnabled)
        XCTAssertFalse(buyStardust.isEnabled)
        XCTAssertTrue(app.staticTexts["需 100 星尘 · 还差 20 星尘"].exists)

        buyCoin.tap()
        let purchaseAlert = app.alerts["兑换邀请码？"]
        XCTAssertTrue(purchaseAlert.waitForExistence(timeout: 5))
        purchaseAlert.buttons["取消"].tap()

        let copyCode = ForumFixture.element("invitation-copy-NS-8F4K-29QM-7X1P", in: app)
        XCTAssertTrue(copyCode.waitForExistence(timeout: 5))
        let heightBeforeCopy = copyCode.frame.height
        copyCode.tap()
        XCTAssertLessThanOrEqual(abs(copyCode.frame.height - heightBeforeCopy), tolerance)
        attachScreenshot(of: app, named: "after-invitations-light")
    }

    func testDarkModeAndSignedOutCommunitySection() throws {
        let app = try launchCommunityTools(signedIn: false, dark: true)
        attachScreenshot(of: app, named: "after-community-tools-dark")

        let invitationsRow = ForumFixture.element("community-row-invitations", in: app)
        for _ in 0..<3 where !(invitationsRow.exists && invitationsRow.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(invitationsRow.waitForExistence(timeout: 5))
        invitationsRow.tap()
        XCTAssertTrue(ForumFixture.title("登录 NodeSeek", in: app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tapRow("community-row-member-search", in: app)
        XCTAssertTrue(ForumFixture.title("查找用户", in: app).waitForExistence(timeout: 5))
        let memberField = ForumFixture.element("member-search-field", in: app)
        memberField.tap()
        memberField.typeText("alice")
        ForumFixture.element("member-search-submit", in: app).tap()
        XCTAssertTrue(ForumFixture.element("member-search-sign-in-button", in: app).waitForExistence(timeout: 5))
    }

    func testAccessibilityTextSizeStacksCommunityTiles() throws {
        let app = try launchCommunityTools(
            signedIn: true,
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityLarge"]
        )
        let recommendedTile = ForumFixture.element("community-tile-recommended", in: app)
        let luckyTile = ForumFixture.element("community-tile-lucky", in: app)
        XCTAssertTrue(recommendedTile.waitForExistence(timeout: 5))
        for _ in 0..<2 where !luckyTile.exists {
            app.swipeUp()
        }
        XCTAssertTrue(luckyTile.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            recommendedTile.frame.maxY,
            luckyTile.frame.minY + tolerance,
            "Community featured tiles stack vertically at accessibility text sizes."
        )
        attachScreenshot(of: app, named: "after-community-tools-accessibility")
    }

    private func tapRow(_ identifier: String, in app: XCUIApplication, line: UInt = #line) {
        let row = ForumFixture.element(identifier, in: app)
        for _ in 0..<4 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing row \(identifier)", line: line)
        row.tap()
    }

    private func popBack(to expectedTitle: String, in app: XCUIApplication, line: UInt = #line) {
        let namedBack = app.navigationBars.buttons[expectedTitle].firstMatch
        if namedBack.exists && namedBack.isHittable {
            namedBack.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(ForumFixture.title(expectedTitle, in: app).waitForExistence(timeout: 5), line: line)
    }

    private func assertReadableColumn(in app: XCUIApplication, elementIdentifier: String, line: UInt = #line) {
        let list = app.collectionViews.containing(.any, identifier: elementIdentifier).firstMatch
        let cell = list.cells.containing(.any, identifier: elementIdentifier).firstMatch
        ForumFixture.assertReadableRow(cell, in: list, line: line)
    }

    private func launchCommunityTools(
        signedIn: Bool,
        dark: Bool = false,
        extraArguments: [String] = []
    ) throws -> XCUIApplication {
        let app = XCUIApplication()
        let author: [String: Any] = ["uid": 9_900_101, "name": "林风"]
        let commenter: [String: Any] = ["uid": 9_900_102, "name": "云端观察"]
        let threadComments: [[String: Any]] = (0...4).map { floor in
            [
                "commentId": 700 + floor,
                "floorIndex": floor,
                "poster": floor == 0 ? author : commenter,
                "time": ["createdDate": "2026-11-17T08:00:00.000Z"],
                "markdown": floor == 0 ? "自建家庭双栈网络实践记录。" : "第 \(floor) 楼：感谢分享详细配置。",
                "likeCount": 2,
                "upvoteCount": 0,
                "blocked": false
            ]
        }

        let responses: [String: [String: Any]] = [
            "https://www.nodeseek.com/?sortBy=replyTime": ["posts": [], "pinnedPosts": [], "hasNextPage": false],
            "/api/content/list-categories": ["success": true, "data": []],
            "https://www.nodeseek.com/award": [
                "posts": [
                    [
                        "id": 301,
                        "title": "自建家庭双栈网络与 BGP 路由分流实践笔记",
                        "author": "林风",
                        "authorID": 9_900_101,
                        "avatar": "",
                        "category": "技术",
                        "categoryKey": "tech",
                        "views": 1840,
                        "replies": 42,
                        "activityDate": "2026-11-18T03:20:00.000Z",
                        "pinned": false
                    ],
                    [
                        "id": 302,
                        "title": "2026 秋季欧洲免税区独服与线路横向对比",
                        "author": "云端观察",
                        "authorID": 9_900_102,
                        "avatar": "",
                        "category": "测评",
                        "categoryKey": "review",
                        "views": 960,
                        "replies": 19,
                        "activityDate": "2026-11-17T18:45:00.000Z",
                        "pinned": false
                    ]
                ],
                "pinnedPosts": [],
                "hasNextPage": false
            ],
            "https://www.nodeseek.com/post-301-1": [
                "postId": 301,
                "title": "自建家庭双栈网络与 BGP 路由分流实践笔记",
                "categoryWord": "技术",
                "views": "1840",
                "postPage": 1,
                "postPageCount": 1,
                "collectionCount": 5,
                "op": author,
                "comments": threadComments
            ],
            "/api/account/find/alice": [
                "memberList": [
                    [
                        "member_id": 9_900_101,
                        "member_name": "alice_dev",
                        "bio": "专注网络协议与分布式系统构建",
                        "coin": 1350
                    ],
                    [
                        "member_id": 9_900_102,
                        "member_name": "alice_cloud",
                        "bio": "VPS 测评与国际回程线路记录",
                        "coin": 420
                    ]
                ]
            ],
            "/api/content/floor-data?postId=301&time=1700000000000": [
                "success": true,
                "data": [
                    ["floor_id": 0, "member_id": 9_900_101, "member_name": "林风"],
                    ["floor_id": 1, "member_id": 9_900_102, "member_name": "云端观察"],
                    ["floor_id": 2, "member_id": 9_900_102, "member_name": "云端观察"],
                    ["floor_id": 3, "member_id": 9_900_103, "member_name": "北极星"],
                    ["floor_id": 4, "member_id": 9_900_104, "member_name": "清风"]
                ]
            ],
            "https://api.drand.sh/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/public/3485631": [
                "round": 3_485_631,
                "randomness": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            ],
            "/api/admin/ruling/page-1": [
                "total": 2,
                "data": [
                    [
                        "id": 801,
                        "target_member_id": 9_900_201,
                        "target_member_name": "推广小号",
                        "admin_member_id": 9_900_001,
                        "admin_member_name": "版务甲",
                        "post_id": 301,
                        "floor_index": 3,
                        "request": #"{"coin":{"coin_diff":-10,"reason":"发布无关推广链接"},"hideComment":{"status":true}}"#,
                        "created_at": "2026-11-17T08:30:00.000Z"
                    ],
                    [
                        "id": 800,
                        "target_member_id": 9_900_101,
                        "target_member_name": "林风",
                        "admin_member_id": 9_900_001,
                        "admin_member_name": "版务甲",
                        "post_id": 301,
                        "floor_index": 0,
                        "request": #"{"postSummary":{"award":true,"category":"tech"}}"#,
                        "created_at": "2026-11-16T14:10:00.000Z"
                    ]
                ]
            ],
            "/api/admin/ruling/id-801": [
                "total": 1,
                "data": [
                    [
                        "id": 801,
                        "target_member_id": 9_900_201,
                        "target_member_name": "推广小号",
                        "admin_member_id": 9_900_001,
                        "admin_member_name": "版务甲",
                        "post_id": 301,
                        "floor_index": 3,
                        "request": #"{"coin":{"coin_diff":-10,"reason":"发布无关推广链接"},"hideComment":{"status":true}}"#,
                        "created_at": "2026-11-17T08:30:00.000Z"
                    ]
                ]
            ],
            "/api/invite/config": [
                "payment": [
                    "coin": ["enabled": true, "cost": 1000],
                    "stardust": ["enabled": true, "cost": 100]
                ]
            ],
            "/api/invite/list?page=1": [
                "total": 2,
                "data": [
                    ["code": "NS-8F4K-29QM-7X1P", "applied": false, "created_at": "2026-11-17T10:00:00.000Z"],
                    ["code": "NS-3B9L-62WT-4C8R", "applied": true, "created_at": "2026-11-05T16:20:00.000Z"]
                ]
            ]
        ]

        let encodedResponses = try responses.mapValues {
            try JSONSerialization.data(withJSONObject: $0).base64EncodedString()
        }
        let auth: [String: Any] = signedIn
            ? [
                "ready": true,
                "user": [
                    "id": 9_900_315,
                    "name": "测试用户",
                    "coins": 1280,
                    "stardust": 80
                ]
            ]
            : ["ready": true]
        let fixture: [String: Any] = [
            "authentication": auth,
            "responses": encodedResponses
        ]
        app.launchEnvironment["NODESEEK_UI_TEST_WEBSITE"] =
            String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchArguments += ["-appearance", dark ? "dark" : "light"] + extraArguments
        app.launch()

        let myTab = ForumFixture.tab("我的", in: app)
        XCTAssertTrue(myTab.waitForExistence(timeout: 8))
        myTab.tap()

        if signedIn {
            XCTAssertTrue(app.staticTexts["测试用户"].waitForExistence(timeout: 5))
        }

        let tools = app.buttons["社区工具"].firstMatch
        for _ in 0..<3 where !(tools.exists && tools.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        XCTAssertTrue(ForumFixture.title("社区工具", in: app).waitForExistence(timeout: 5))
        return app
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
