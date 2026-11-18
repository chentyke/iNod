import NodeSeekCore
import Testing
@testable import NodeSeekClient

@Test func dailyProgressResourceTargetsTodayEndpointAndRequiresSignIn() {
    let resource = WebsiteResource.dailyProgress
    #expect(resource.path == "/api/progress/today")
    #expect(resource.requiresLogin)
}
