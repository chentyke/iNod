import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

struct LiveStreamingCheckerTests {
    @Test func mapsServiceResultsOntoTheScreenContract() async throws {
        let service = QualityStreamingService { request, _ in
            switch request.url?.host() {
            case "www.netflix.com": .init(statusCode: 451, connectionFamily: .ipv6)
            case "www.disneyplus.com": .init(statusCode: 401)
            case "www.primevideo.com": .init(statusCode: 302)
            case "www.youtube.com":
                .init(body: Data(#"{"type":"video","provider_name":"YouTube","html":"<iframe src=\"https://www.youtube.com/embed/M7lc1UVf-VE?feature=oembed\"></iframe>"}"#.utf8))
            default: throw URLError(.timedOut)
            }
        }
        let checker = LiveStreamingChecker(service: service)
        var snapshots: [[StreamingSampleCheck]] = []
        for await snapshot in checker.run() { snapshots.append(snapshot) }
        #expect(snapshots.count == 2)
        #expect(snapshots[0].allSatisfy { $0.result.status == .running(.init()) })
        let final = try #require(snapshots.last)
        #expect(final.map(\.platform) == StreamingPlatform.allCases)
        #expect(final.map(\.result.value) == [.legallyRestricted, .authenticationRequired, .redirected, .embedMetadata, nil])
        #expect(final[0].family == .v6)
        #expect(final[4].result.status == .failed(.init(.timedOut)))
        #expect(final[3].sampleTitle == "Embedded Web Player Customization")
        #expect(checker.youTubeSampleVideoID == "M7lc1UVf-VE")
    }

    @Test func forwardsPlayerEventsAndKeepsTheFirstOutcome() throws {
        let checker = LiveStreamingChecker()
        #expect(checker.playbackCheck(for: .netflix) == nil)
        var youTube = try #require(checker.playbackCheck(for: .youTube))
        #expect(!youTube.isSample)
        youTube.receive(.youTubeAutoplayBlocked)
        youTube.receive(.timeout)
        #expect(youTube.result.value == .autoplayBlocked)

        var tikTok = try #require(checker.playbackCheck(for: .tikTok))
        let error = Data(#"{"x-tiktok-player":true,"type":"onPlayerError","value":{"errorCode":3001}}"#.utf8)
        tikTok.receive(.tikTokMessage(error, origin: "https://evil.example"))
        #expect(!tikTok.result.status.isFinished)
        tikTok.receive(.tikTokMessage(error, origin: "https://www.tiktok.com"))
        #expect(tikTok.result.value == .playerError(code: 3001))

        var dismissed = try #require(checker.playbackCheck(for: .youTube))
        dismissed.receive(.cancel)
        #expect(dismissed.result == .cancelled)
    }

    @Test func checksRegionRulesOnlyForValidInput() async {
        let service = QualityStreamingService { _, _ in
            .init(body: Data(#"{"items":[{"id":"M7lc1UVf-VE","contentDetails":{"regionRestriction":{"blocked":["DE"]}}}]}"#.utf8))
        }
        let checker = LiveStreamingChecker(service: service)
        let blocked = await checker.checkYouTubeRegion(videoID: "M7lc1UVf-VE", countryCode: "de", apiKey: "test")
        #expect(blocked.countryCode == "DE")
        #expect(blocked.result.value == .blocked)
        let allowed = await checker.checkYouTubeRegion(videoID: "M7lc1UVf-VE", countryCode: "US", apiKey: "test")
        #expect(allowed.result.value == .allowed)
        #expect(!YouTubeRegionCheck.isValidVideoID("short"))
        #expect(!YouTubeRegionCheck.isValidCountryCode("USA"))
        #expect(YouTubeRegionCheck.isValidCountryCode("us"))
    }
}
