#if DEBUG
import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

@MainActor
struct CategoryStoreTests {
    @Test func freshCategoriesDoNotRecheckLoginUnlessExplicitlyRefreshed() async throws {
        let snapshot = try JSONDecoder().decode(AuthenticationSnapshot.self, from: Data(#"""
        {"ready":true,"user":{"id":42,"name":"Test reader"}}
        """#.utf8))
        var authenticationReads = 0
        let website = SiteDataStore(disk: nil) {
            authenticationReads += 1
            return snapshot
        }
        website.responsesForUITests = ["/api/content/list-categories": Data(#"""
        {"success":true,"data":[{"key":"daily","cn_text":"日常","adminOnly":false}]}
        """#.utf8)]
        let categories = CategoryStore(website: website)

        await categories.refresh()
        #expect(categories.items.map(\.id) == ["", "daily"])
        #expect(authenticationReads == 1)

        // The viewer is known, but the background WebKit login check needs refreshing.
        website.observe(snapshot)
        await categories.refresh()
        #expect(authenticationReads == 1)

        await categories.refresh(force: true)
        #expect(authenticationReads == 2)
    }
}
#endif
