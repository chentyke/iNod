import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

@Test func websiteResourceEncodesSearchAndPreservesLedgerFilters() throws {
    let search = WebsiteResource.memberSearch("a/b?#%")
    #expect(search.path == "/api/account/find/a%2Fb%3F%23%25")
    let resource = WebsiteResource.stardust(memberID: 4, type: "transfer", reference: "002", peer: "7", beforeID: 80)
    let query = try #require(URLComponents(string: resource.path)?.queryItems)
    #expect(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value) }) == [
        "member_id": "4", "count": "10", "type": "transfer", "ref_id": "002", "peer_id": "7", "before_id": "80"
    ])
    #expect(resource.requiresLogin)
    let unfiltered = WebsiteResource.stardust(memberID: 4, filter: StardustFilter())
    #expect(unfiltered.path == "/api/stardust/list?member_id=4&count=10")
    let filteredFromSpaceLink = WebsiteResource.stardust(
        memberID: 4,
        filter: StardustFilter(type: "upvote", peer: "https://www.nodeseek.com/space/99", reference: " 108 "),
        beforeID: 42
    )
    let filteredQuery = try #require(URLComponents(string: filteredFromSpaceLink.path)?.queryItems)
    #expect(Dictionary(uniqueKeysWithValues: filteredQuery.map { ($0.name, $0.value) }) == [
        "member_id": "4", "count": "10", "type": "upvote", "ref_id": "108", "peer_id": "99", "before_id": "42"
    ])
    #expect(!WebsiteResource.vote(5).requiresLogin)
}

@Test func websiteActionsKeepTheExistingWriteFormats() throws {
    let categories = try JSONDecoder().decode([HomepageCategory].self, from: Data(#"[{"id":"tech","title":"技术","enabled":true}]"#.utf8))
    let homepage = WebsiteAction.saveHomepage(categories).request
    #expect(homepage.path == "/api/homepage")
    let entries = try #require(homepage.body["data"] as? [[String: Any]])
    #expect(entries.first?["category"] as? String == "tech")
    #expect(entries.first?["showInIndex"] as? Bool == true)
    #expect(!WebsiteAction.prepareTransfer(recipientID: 5).request.changesData)
    #expect(WebsiteAction.attend(random: false).request.path == "/api/attendance?random=false")
    #expect(WebsiteAction.attend(random: true).request.path == "/api/attendance?random=true")
    #expect(AccountResource.attendance(2).path == "/api/attendance/board?page=2")
    #expect(AccountResource.attendance(0).path == "/api/attendance/board?page=1")
}

@Test func missingThreadUsesTheListedRankAndConfirmedAccount() throws {
    let decoder = JSONDecoder()
    var post = try decoder.decode(PostSummary.self, from: Data(#"""
    {"id":123,"title":"有阅读限制的帖子","author":"楼主","authorID":1,"avatar":"",
     "category":"日常","categoryKey":"daily","views":1,"replies":0,"activityDate":"","pinned":false,"rank":1}
    """#.utf8))
    func authentication(_ json: String) throws -> AuthenticationSnapshot {
        try decoder.decode(AuthenticationSnapshot.self, from: Data(json.utf8))
    }

    let guest = try authentication(#"{"ready":true,"user":null}"#)
    let lowLevel = try authentication(#"{"ready":true,"user":{"id":2,"name":"读者","coins":0}}"#)
    let eligible = try authentication(#"{"ready":true,"user":{"id":2,"name":"读者","coins":100}}"#)
    let author = try authentication(#"{"ready":true,"user":{"id":1,"name":"楼主","coins":0}}"#)
    let unknownLevel = try authentication(#"{"ready":true,"user":{"id":2,"name":"读者"}}"#)
    let unconfirmed = try authentication(#"{"ready":false,"user":null}"#)
    #expect(PostAccessError.forMissingPost(post, authentication: guest) == .signInRequired)
    #expect(PostAccessError.forMissingPost(post, authentication: lowLevel) == .levelRequired(1))
    #expect(PostAccessError.forMissingPost(post, authentication: eligible) == nil)
    #expect(PostAccessError.forMissingPost(post, authentication: author) == nil)
    #expect(PostAccessError.forMissingPost(post, authentication: unknownLevel) == nil)
    #expect(PostAccessError.forMissingPost(post, authentication: unconfirmed) == nil)

    post.rank = 255
    #expect(PostAccessError.forMissingPost(post, authentication: lowLevel) == nil)
    post.rank = nil
    #expect(PostAccessError.forMissingPost(post, authentication: guest) == nil)
}
