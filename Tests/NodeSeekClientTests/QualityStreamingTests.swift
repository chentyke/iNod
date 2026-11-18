import Foundation
import Testing
@testable import NodeSeekClient

struct QualityStreamingTests {
    @Test func verifiesContentMetadataAndKeepsRestrictionsSeparate() async throws {
        let service = QualityStreamingService { request, upload in
            #expect(upload == nil)
            let url = try #require(request.url)
            switch url.host() {
            case "www.netflix.com":
                #expect(url.path() == "/title/81040344")
                return .init(statusCode: 451, connectionFamily: .ipv6)
            case "www.disneyplus.com":
                return .init(statusCode: 302)
            case "www.primevideo.com":
                return html(#"<head><link href='https://www.primevideo.com/detail/0HAQAA7JM43QWX0H6GUD3IOF70' rel='canonical'></head>"#)
            case "www.youtube.com":
                #expect(url.path() == "/oembed")
                return html(#"{"type":"video","provider_name":"YouTube","html":"<iframe src=\"https://www.youtube.com/embed/M7lc1UVf-VE?feature=oembed\"></iframe>"}"#)
            case "www.tiktok.com":
                return html(#"{"type":"video","provider_name":"TikTok","html":"<blockquote></blockquote>","embed_product_id":"6718335390845095173"}"#)
            default: throw URLError(.badURL)
            }
        }
        let results = await service.run()
        #expect(results.map(\.platform) == QualityStreamingPlatform.allCases)
        #expect(results.map { $0.result.value } == [.legallyRestricted, .redirected, .titlePage, .embedMetadata, .embedMetadata])
        #expect(results[0].connectionFamily == .ipv6)
        #expect(results[0].httpStatus == 451)
    }

    @Test func doesNotTreatAChallengeOrWrongContentAsAccessEvidence() async {
        let service = QualityStreamingService { request, _ in
            switch request.url?.host() {
            case "www.netflix.com": throw URLError(.timedOut)
            case "www.disneyplus.com": return .init(statusCode: 401)
            case "www.primevideo.com":
                return html(#"<head><link rel="canonical" href="https://www.primevideo.com/"></head>"#)
            case "www.youtube.com":
                return html(#"{"type":"video","provider_name":"YouTube","html":"<iframe src=\"https://www.youtube.com/embed/other?feature=oembed\"></iframe>"}"#)
            case "www.tiktok.com": return .init(statusCode: 403)
            default: throw URLError(.badURL)
            }
        }
        let results = await service.run()
        #expect(results[0].result == .failed(.init(.timedOut)))
        #expect(results[1].result.value == .authenticationRequired)
        #expect(results.dropFirst(2).allSatisfy { $0.result.value == .undetermined })
        #expect(results[4].httpStatus == 403)
    }

    @Test func usesPublishedYouTubeRulesForTheSpecifiedCountry() async throws {
        let videoID = "M7lc1UVf-VE"
        let cases: [(String, QualityYouTubeRegionObservation.Rule)] = [
            (#"{"regionRestriction":{"allowed":["JP"]}}"#, .allowed),
            (#"{"regionRestriction":{"allowed":[]}}"#, .blocked),
            (#"{"regionRestriction":{"blocked":["JP"]}}"#, .blocked),
            (#"{"regionRestriction":{"blocked":[]}}"#, .allowed),
            (#"{"regionRestriction":{"allowed":["JP"],"blocked":["JP"]}}"#, .undetermined),
            ("{}", .noPublishedRule)
        ]
        for (rules, expected) in cases {
            let service = QualityStreamingService { request, _ in
                #expect(request.url?.host() == "www.googleapis.com")
                #expect(request.url?.query()?.contains("id=\(videoID)") == true)
                #expect(request.url?.absoluteString.contains("test-key") == false)
                #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == "test-key")
                return html(#"{"items":[{"id":"\#(videoID)","contentDetails":\#(rules)}]}"#)
            }
            let observation = await service.checkYouTubeRegion(videoID: videoID, countryCode: "jp", apiKey: "test-key")
            #expect(observation.countryCode == "JP")
            #expect(observation.result.value == expected)
        }
    }
}

private func html(_ value: String) -> QualityHTTPResponse {
    .init(body: Data(value.utf8))
}
