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
}
