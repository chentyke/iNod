import NodeSeekCore
import WebKit

@MainActor
public enum SitePage {
    public static func make(contentRules: WKContentRuleList? = nil) -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .default()
        if let contentRules { configuration.userContentController.add(contentRules) }
        return WebPage(configuration: configuration)
    }

    static func backgroundReaderRules() async -> WKContentRuleList? {
        let rules = #"""
        [
            {
                "trigger": {
                    "url-filter": "^https://(www[.])?nodeseek[.]com/",
                    "resource-type": ["image", "style-sheet", "font"]
                },
                "action": { "type": "block" }
            },
            {
                "trigger": {
                    "url-filter": "^https://(www[.])?nodeseek[.]com/assets/markdownEditor-[a-zA-Z0-9_-]+[.]js$",
                    "resource-type": ["script"]
                },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "^https://(www[.])?nodeseek[.]com/cdn-cgi/" },
                "action": { "type": "ignore-previous-rules" }
            }
        ]
        """#
        guard let store = WKContentRuleListStore.default() else { return nil }
        let identifier = "NodeSeekBackgroundReader-v1"
        if let existing = try? await store.contentRuleList(forIdentifier: identifier) { return existing }
        return try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules)
    }

    static func authentication(from page: WebPage) async throws -> AuthenticationSnapshot {
        guard page.url?.scheme == "https",
              let host = page.url?.host()?.lowercased(),
              ["www.nodeseek.com", "nodeseek.com"].contains(host),
              let json = try await page.callJavaScript(SiteScripts.readiness) as? String else {
            throw SiteError.invalidResponse
        }
        let snapshot = try JSONDecoder().decode(AuthenticationSnapshot.self, from: Data(json.utf8))
        if let user = snapshot.user, user.id <= 0 || user.name.isEmpty { throw SiteError.invalidResponse }
        return snapshot
    }
}
