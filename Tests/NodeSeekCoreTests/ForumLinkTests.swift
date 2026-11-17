import Foundation
import Testing
@testable import NodeSeekCore

@Test func forumLinksNormalizeCommonWebsiteForms() throws {
    for value in ["https://www.nodeseek.com/post-123-2#11","http://nodeseek.com/post-123-2#11","/post-123-2#11","https://NODESEEK.COM:443/post-123-2#11"] {
        let address = try #require(PostAddress(value))
        #expect(ForumLink.parse(value) == .native(.post(address)))
        #expect(address.page == 2)
        #expect(address.floor == 11)
    }
    #expect(PostAddress("https://www.nodeseek.com/post-123")?.page == 1)
    #expect(ForumLink.parse("/space/9#comments") == .native(.member(id:9,section:"comments")))
    #expect(ForumLink.parse("http://nodeseek.com/space/9#comments") == .native(.member(id:9,section:"comments")))
}

@Test func forumLinksRejectImpersonatingHostsAndCredentials() {
    for value in ["https://www.nodeseek.com.evil.test/post-1-1","https://nodeseek.com@evil.test/post-1-1","https://someone@nodeseek.com/post-1-1","https://nodeseek.com:8443/post-1-1","javascript:alert(1)","https://example.com/post-1-1"] {
        #expect(ForumLink.parse(value) == nil)
    }
}

@Test func forumRedirectsResolveOnlyInternalDestinations() throws {
    let address = try #require(PostAddress("/post-123-2#11"))
    #expect(ForumLink.parse("/jump?to=https%3A%2F%2Fnodeseek.com%2Fpost-123-2%2311") == .native(.post(address)))
    #expect(ForumLink.parse("/jump?to=https%3A%2F%2Fexample.com") == nil)
    #expect(ForumLink.parse("https://nodeseek.com/setting#security") == .website(URL(string:"https://www.nodeseek.com/setting#security")!))
}

@Test func categoriesSearchAndUnknownForumPagesStayInApp() {
    #expect(ForumLink.parse("/categories/tech?sortBy=postTime") == .native(.feed(category:"tech",sort:.postTime)))
    #expect(ForumLink.parse("/search?q=C%2B%2B&category=tech") == .native(.search(query:"C++",category:"tech",sort:.replyTime)))
    #expect(ForumLink.parse("/search?q=swift&page=2") == .website(URL(string:"https://www.nodeseek.com/search?q=swift&page=2")!))
    #expect(ForumLink.parse("/award") == .native(.recommended))
    #expect(ForumLink.parse("/categories/new-board") == .native(.feed(category:"new-board",sort:.replyTime)))
    #expect(ForumLink.parse("/categories/../setting") == .website(URL(string:"https://www.nodeseek.com/setting")!))
}

@Test func bareURLsAndMarkdownLinksHaveExplicitLinkAttributes() {
    let text = ForumText.attributed("中文😀 https://nodeseek.com/post-123-1 与 [主页](/space/9)")
    let links = text.runs.compactMap(\.link)
    #expect(links.contains(URL(string:"https://nodeseek.com/post-123-1")!))
    #expect(links.contains(URL(string:"https://www.nodeseek.com/space/9")!))
    #expect(!text.characters.isEmpty)
}

@Test func codeLinksRemainPlainAndFragmentsUseTheCurrentPost() {
    let current = NodeSeekRoute.thread(id:123,page:2).url
    let text = ForumText.attributed("`https://nodeseek.com/post-1-1` [#11](#11)",baseURL:current)
    #expect(text.runs.compactMap(\.link) == [URL(string:"https://www.nodeseek.com/post-123-2#11")!])
    let plain = ForumText.attributed("*原文* https://nodeseek.com/space/9",markdown:false)
    #expect(String(plain.characters).hasPrefix("*原文*"))
    #expect(plain.runs.compactMap(\.link) == [URL(string:"https://nodeseek.com/space/9")!])
}

@Test func replyReferencesLinkToTheMentionAndTheCorrectFloorPage() {
    let postURL = NodeSeekRoute.thread(id: 123, page: 2).url
    let text = ForumText.attributed("@SampleReader42 请看 #8，也可以参考 #11 和 @示例读者-42", baseURL: postURL)
    #expect(String(text.characters) == "@SampleReader42 请看 #8，也可以参考 #11 和 @示例读者-42")
    #expect(text.runs.compactMap(\.link).map { ForumLink.parse($0.absoluteString) } == [
        .native(.mention("SampleReader42")), .native(.post(PostAddress("/post-123-1#8")!)),
        .native(.post(PostAddress("/post-123-2#11")!)), .native(.mention("示例读者-42"))
    ])
}

@Test func replyReferencesKeepMarkdownLinksCodeAndEmailIntact() {
    let postURL = NodeSeekRoute.thread(id: 123, page: 1).url
    let text = ForumText.attributed("`@Alice #7` @SampleReader42 [#8](#8) test@example.com #8bit #9.5 [@Bob](/space/9)", baseURL: postURL)
    #expect(text.runs.compactMap(\.link).map(\.absoluteString) == [
        "nsapp://mention?name=SampleReader42", "https://www.nodeseek.com/post-123-1#8",
        "mailto:test@example.com", "https://www.nodeseek.com/space/9"
    ])
    #expect(ForumText.attributed("@Alice #7").runs.compactMap(\.link).isEmpty)
}

@Test func websiteOnlyPagesHaveRoutesThatStayOnTheWebsite() {
    let settings = NodeSeekRoute.settings(section: "contact").url
    #expect(settings.absoluteString == "https://www.nodeseek.com/setting#contact")
    #expect(ForumLink.parse(settings.absoluteString) == .website(settings))
    let signIn = NodeSeekRoute.signIn.url
    #expect(signIn.absoluteString == "https://www.nodeseek.com/signIn.html")
    #expect(ForumLink.parse(signIn.absoluteString) == .website(signIn))
}
