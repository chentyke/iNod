import Foundation
import NodeSeekCore
import Testing

struct StreamingSampleTests {
    @Test func samplePlaysBackMixedOutcomesOnePlatformAtATime() async {
        var snapshots: [[StreamingSampleCheck]] = []
        for await snapshot in SampleStreamingChecker(pace: 0.01).run() { snapshots.append(snapshot) }
        #expect(snapshots.count == StreamingPlatform.allCases.count + 1)
        #expect(snapshots.last == SampleStreamingChecker.results(at: snapshots.last?.first?.queriedAt ?? .now).enumerated().map { index, check in
            var check = check
            check.queriedAt = snapshots.last?[index].queriedAt
            return check
        })
        let outcomes = Set(snapshots.last?.compactMap(\.result.value) ?? [])
        #expect(outcomes.count >= 3, "The sample shows several kinds of answer")
    }

    @Test func samplePlaybackFinishesWithItsScriptOrStops() throws {
        let checker = SampleStreamingChecker()
        var youTube = try #require(checker.playbackCheck(for: .youTube))
        var tikTok = try #require(checker.playbackCheck(for: .tikTok))
        #expect(checker.playbackCheck(for: .primeVideo) == nil)
        youTube.receive(.sampleFinished)
        tikTok.receive(.sampleFinished)
        #expect(youTube.result.value == .played)
        #expect(tikTok.result.value == .autoplayBlocked)

        var dismissed = try #require(checker.playbackCheck(for: .youTube))
        dismissed.receive(.cancel)
        dismissed.receive(.sampleFinished)
        #expect(dismissed.result == .cancelled)
    }

    @Test func wordingNeverClaimsPlayback() {
        #expect(StreamingEvidence.titlePage.title == "片名页可访问")
        #expect(StreamingEvidence.embedMetadata.title == "嵌入信息可取得")
        #expect(StreamingPlaybackOutcome.playerError(code: 150).title == "播放器错误 150")
        #expect(YouTubeRegionRule.noPublishedRule.title == "未发布地区规则")
    }
}
