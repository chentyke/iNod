import AppKit
import WebKit

@main private struct WebsiteChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.loadsSubresources = false
        let page = WebPage(configuration: configuration)
        try await checkAccountHTML(in: page)
        try await checkPostAccess(in: page)
    }

    @MainActor private static func checkAccountHTML(in page: WebPage) async throws {
        for try await event in page.load(html: "<!doctype html><html><body>Local checks</body></html>", baseURL: URL(string: "https://www.nodeseek.com")!) {
            if event == .finished { break }
        }
        let script = #"""
        const fetch=async()=>({ok:true,json:async()=>({comments:[{post_id:1,floor_id:3,title:'example',text:'<p>hello <a href="https://example.com">link</a> &amp; test</p><p>next<br>line<img alt=":xhj003:"><script>throw new Error("must not run")</script></p>'}]})});
        """# + AccountScripts.read
        let result = try await page.callJavaScript(script, arguments: ["path":"/api/content/list-comments?uid=9&page=1","kind":"replies","page":1,"userID":9,"memberID":9]) as! String
        let object = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String: Any]
        let items = object["items"] as! [[String: Any]]
        precondition(items[0]["excerpt"] as? String == "hello link & test next line:xhj003:")
        let origin = try await page.callJavaScript("return location.origin;") as! String
        precondition(origin == "https://www.nodeseek.com")
        print("HTML reply extraction passed in WebKit: entities, links, line breaks, image labels, and inert scripts. No network requests sent.")
    }

    @MainActor private static func checkPostAccess(in page: WebPage) async throws {
        let url = URL(string: "https://www.nodeseek.com/post-123-1")!
        for try await event in page.load(html: "<!doctype html><html><body></body></html>", baseURL: url) {
            if event == .finished { break }
        }

        func response(_ result: Any?) throws -> [String: Any] {
            if let document = result as? [String: String] {
                return try document.mapValues {
                    try JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed)
                }
            }
            let json = result as! String
            let failure = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            precondition(failure["__error"] != nil || failure["__postAccess"] != nil)
            return failure
        }

        func read(_ extraction: String, html: String, url: URL = url, status: Int = 200, challenge: Bool = false,
                  checkingPostAccess: Bool = true) async throws -> [String: Any] {
            let mockFetch = #"""
            const fetch = async () => ({
                ok: status < 400, status, url: path, text: async () => html,
                headers: new Headers(challenge ? {'cf-mitigated': 'challenge'} : {})
            });
            """#
            let script = mockFetch + SiteScripts.document(extraction, checkingPostAccess: checkingPostAccess)
            let result = try await page.callJavaScript(script, arguments: [
                "path": url.absoluteString, "html": html, "status": status, "challenge": challenge
            ])
            return try response(result)
        }

        let levelMessage = "查看本帖需要<b>Lv 5</b>，您的权限不足😑，请赚取🍗升级您的用户等级"
        func forumPage(_ content: String) -> String {
            "<div id=\"nsk-body\"><div id=\"nsk-body-left\">\(content)</div></div>"
        }
        for status in [200, 403, 404] {
            let denied = try await read(SiteScripts.thread, html: forumPage("<div>\(levelMessage)</div>"), status: status)
            precondition(denied["__postAccess"] as? String == "level" && denied["rank"] as? Int == 5)
            precondition(denied["__needsWebsite"] == nil)
        }
        let noRank = try await read(SiteScripts.thread, html: forumPage("您的权限不足，请赚取🍗升级您的用户等级"))
        precondition(noRank["__postAccess"] as? String == "level" && noRank["rank"] is NSNull)
        let guest = try await read(SiteScripts.thread, html: forumPage("本帖需要注册用户才能查看😭"), status: 403)
        precondition(guest["__postAccess"] as? String == "signIn")
        for message in ["本帖已经被用户设为私有，您没有阅读权限", "查看本帖需要Lv255，您的权限不足"] {
            let privatePost = try await read(SiteScripts.thread, html: forumPage(message), status: 404)
            precondition(privatePost["__postAccess"] as? String == "private")
        }

        let challenge = try await read(SiteScripts.thread, html: "<title>Just a moment...</title>", status: 403, challenge: true)
        precondition(challenge["__needsWebsite"] as? Bool == true && challenge["__postAccess"] == nil)
        let missing = try await read(SiteScripts.thread, html: forumPage("帖子不存在"), status: 404)
        precondition(missing["__error"] as? String == "官网请求失败 (404)" && missing["__needsWebsite"] as? Bool == false)
        let genericNotFound = try await read(SiteScripts.thread, html: forumPage("404 Not Found😭"), status: 404)
        precondition(genericNotFound["__status"] as? Int == 404 && genericNotFound["__postAccess"] == nil)

        let config = Data(#"{"allCategory":[],"postData":{"postId":123,"rank":5,"views":42,"comments":[{"blocked":true},{"blocked":false}]}}"#.utf8)
        let bootstrap = "<script id=\"temp-script\" type=\"application/json\">\(config.base64EncodedString())</script>"
        let readable = try await read(SiteScripts.thread, html: bootstrap + forumPage("<div class=\"post-content\">\(levelMessage)</div>"))
        let post = readable["content"] as? [String: Any]
        precondition(post?["rank"] as? Int == 5 && post?["views"] as? String == "42", "\(readable)")
        precondition((post?["comments"] as? [Any])?.count == 1)

        let markdown = "## 引用\n\n> \"原文\""
        let loaded = try await page.callJavaScript(
            "window.__config__ = {user: {member_id: 7, member_name: '读者'}};\n"
                + SiteScripts.loadedDocument("return JSON.stringify(markdown);"),
            arguments: ["markdown": markdown]
        )
        let loadedDocument = try response(loaded)
        let auth = loadedDocument["authentication"] as? [String: Any]
        precondition(loadedDocument["content"] as? String == markdown)
        precondition(auth?["ready"] as? Bool == true)
        precondition((auth?["user"] as? [String: Any])?["id"] as? Int == 7)

        let feedHTML = bootstrap + """
        <ul><li class="post-list-item"><div class="post-title">
            <a href="/post-123-1">有阅读限制的帖子</a><span><svg><use href="#lock"></use></svg>5</span>
        </div></li><li class="post-list-item"><div class="post-title">
            <a href="/post-124-1">公开帖子</a>
        </div></li></ul>
        """
        let feed = try await read(SiteScripts.feed(), html: feedHTML, checkingPostAccess: false)
        guard let content = feed["content"] as? [String: Any], let posts = content["posts"] as? [[String: Any]], posts.count == 2 else {
            preconditionFailure("\(feed)")
        }
        precondition(posts[0]["title"] as? String == "有阅读限制的帖子" && posts[0]["rank"] as? Int == 5)
        precondition(posts[1]["rank"] is NSNull)
        print("Post reading restrictions passed in WebKit: feed rank, readable posts, level, sign-in, private, and verification.")

        let carouselConfig = Data(#"""
        {"allCategory":[{"key":"daily","cn_text":"日常"}],"rotateTopics":[
            {"postId":2,"titleText":"论坛公告","category":"daily","op":{"uid":102,"name":"SampleAuthor","avatar":"/avatar/102.png"},
             "views":"1,204","comments":8,"rank":3,"lastCommentDate":"2026-11-13T01:23:45.000Z"},
            {"postId":3,"titleText":"新手指南","category":"dev","categoryWord":"Dev"},
            {"postId":2,"titleText":"重复的公告"},
            {"postId":4,"titleText":"已屏蔽的公告","blocked":true}
        ]}
        """#.utf8)
        let carouselHTML = """
        <script id="temp-script" type="application/json">\(carouselConfig.base64EncodedString())</script>
        <div class="topic-carousel-wrapper"><div class="post-list-item topic-carousel-item"><div class="post-title">
            <a href="/post-3-1">网页生成的轮播项</a>
        </div></div></div>
        <ul><li class="post-list-item"><div class="post-title"><a href="/post-2-1">重复的公告</a></div></li>
        <li class="post-list-item"><div class="post-title"><a href="/post-5-1">普通帖子</a></div></li>
        <li class="post-list-item blocked-post"><div class="post-title"><a href="/post-6-1">已屏蔽的普通帖子</a></div></li></ul>
        <div aria-label="pagination"><a href="/page-2">2</a></div>
        """
        func readFeed(includeBlocked: Bool = false, path: String = "/") async throws -> [String: Any] {
            let url = URL(string: path, relativeTo: url)!.absoluteURL
            let result = try await read(SiteScripts.feed(includeBlocked: includeBlocked), html: carouselHTML, url: url, checkingPostAccess: false)
            return result["content"] as! [String: Any]
        }
        func postIDs(_ feed: [String: Any], key: String) -> [Int] {
            (feed[key] as! [[String: Any]]).map { $0["id"] as! Int }
        }

        let firstPage = try await readFeed()
        precondition(postIDs(firstPage, key: "pinnedPosts") == [2, 3])
        precondition(postIDs(firstPage, key: "posts") == [5])
        precondition(firstPage["hasNextPage"] as? Bool == true)
        let pin = (firstPage["pinnedPosts"] as! [[String: Any]])[0]
        precondition(pin["pinned"] as? Bool == true && pin["rank"] as? Int == 3)
        precondition(pin["category"] as? String == "日常" && pin["authorID"] as? Int == 102)
        precondition(pin["views"] as? Int == 1204 && pin["replies"] as? Int == 8)

        let includingBlocked = try await readFeed(includeBlocked: true)
        precondition(postIDs(includingBlocked, key: "pinnedPosts") == [2, 3, 4])
        precondition(postIDs(includingBlocked, key: "posts") == [5, 6])
        let laterPage = try await readFeed(path: "/page-2")
        precondition(postIDs(laterPage, key: "pinnedPosts").isEmpty)
        precondition(postIDs(laterPage, key: "posts") == [2, 5])
        precondition(laterPage["hasNextPage"] as? Bool == false)
        let search = try await readFeed(path: "/search?q=example")
        precondition(postIDs(search, key: "pinnedPosts").isEmpty)
        print("Pinned feed checks passed in WebKit: carousel order, duplicates, blocked posts, metadata, and pagination.")
    }
}
