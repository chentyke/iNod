import Foundation
import Testing
@testable import NodeSeekClient

struct QualityStreamingPlaybackTests {
    @Test func checksForAdvancingPlaybackAndDoesNotCountASeek() throws {
        var check = try #require(QualityStreamingService().playbackCheck(for: .youTube))
        let start = ContinuousClock.now
        check.receiveYouTubeState(5)
        check.receiveYouTubePosition(4, at: start)
        check.receiveYouTubePosition(5, at: start.advanced(by: .seconds(1)))
        #expect(!check.result.status.isFinished)
        check.receiveYouTubeState(1)
        check.receiveYouTubePosition(5, at: start.advanced(by: .seconds(2)))
        check.receiveYouTubePosition(40, at: start.advanced(by: .seconds(3)))
        #expect(!check.result.status.isFinished)
        check.receiveYouTubeState(3)
        check.receiveYouTubePosition(42, at: start.advanced(by: .seconds(5)))
        #expect(!check.result.status.isFinished)
        check.receiveYouTubeState(1)
        check.receiveYouTubePosition(43, at: start.advanced(by: .seconds(6)))
        check.receiveYouTubePosition(44, at: start.advanced(by: .seconds(7)))
        #expect(check.result.value == .played)
        check.receiveYouTubeError(5)
        #expect(check.result.value == .played)
    }

    @Test func understandsTikTokMessagesFromTheExpectedOrigin() throws {
        var check = try #require(QualityStreamingService().playbackCheck(for: .tikTok))
        let start = ContinuousClock.now
        let state = Data(#"{"x-tiktok-player":true,"type":"onStateChange","value":1}"#.utf8)
        let previous = Data(#"{"x-tiktok-player":true,"type":"onCurrentTime","value":{"currentTime":2,"duration":12}}"#.utf8)
        let advanced = Data(#"{"x-tiktok-player":true,"type":"onCurrentTime","value":{"currentTime":3,"duration":12}}"#.utf8)
        let error = Data(#"{"x-tiktok-player":true,"type":"onPlayerError","value":{"errorCode":3002}}"#.utf8)
        check.receiveTikTokMessage(error, origin: "https://www.tiktok.com.example")
        check.receiveYouTubeState(1)
        check.receiveTikTokMessage(previous, origin: "https://www.tiktok.com", at: start)
        check.receiveTikTokMessage(advanced, origin: "https://www.tiktok.com", at: start.advanced(by: .seconds(1)))
        #expect(!check.result.status.isFinished)
        check.receiveTikTokMessage(state, origin: "https://www.tiktok.com")
        check.receiveTikTokMessage(previous, origin: "https://www.tiktok.com", at: start)
        check.receiveTikTokMessage(advanced, origin: "https://www.tiktok.com", at: start.advanced(by: .seconds(1)))
        #expect(check.videoID == "6718335390845095173")
        #expect(check.result.value == .played)
    }

    @Test func identifiesAutoplayFailureAndLeavesUnsupportedPlatformsWithoutAPlaybackCheck() throws {
        let streaming = QualityStreamingService()
        var youtube = try #require(streaming.playbackCheck(for: .youTube))
        var tiktok = try #require(streaming.playbackCheck(for: .tikTok))
        youtube.receiveYouTubeAutoplayBlocked()
        tiktok.receiveTikTokMessage(
            Data(#"{"x-tiktok-player":true,"type":"onPlayerError","value":{"errorCode":3002}}"#.utf8),
            origin: "https://www.tiktok.com"
        )
        #expect(youtube.result.value == .autoplayBlocked)
        #expect(tiktok.result.value == .autoplayBlocked)
        var retry = try #require(streaming.playbackCheck(for: .tikTok))
        retry.receiveTikTokMessage(
            Data(#"{"x-tiktok-player":true,"type":"onPlayerError","value":{"errorCode":3001}}"#.utf8),
            origin: "https://www.tiktok.com"
        )
        #expect(retry.result.value == .playerError(code: 3001))
        #expect(streaming.playbackCheck(for: .netflix) == nil)
        #expect(streaming.playbackCheck(for: .disneyPlus) == nil)
        #expect(streaming.playbackCheck(for: .primeVideo) == nil)
    }
}
