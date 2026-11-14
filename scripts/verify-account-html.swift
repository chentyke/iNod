import AppKit
import WebKit

@main private struct AccountHTMLChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        let page = WebPage(configuration: configuration)
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
}
