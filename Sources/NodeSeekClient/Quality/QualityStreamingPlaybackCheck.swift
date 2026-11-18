import Foundation
import NodeSeekCore

/// Interprets one attempt from a visible official player for the specified sample.
public struct QualityStreamingPlaybackCheck: Sendable {
    public enum Outcome: Codable, Equatable, Sendable {
        case played
        case autoplayBlocked
        case playerError(code: Int)
    }

    public let platform: QualityStreamingPlatform
    public let videoID: String
    public let startedAt: Date
    public private(set) var result: QualityResult<Outcome> = .running(.init())

    private var playing = false
    private var firstPosition: (seconds: Double, at: ContinuousClock.Instant)?

    init(platform: QualityStreamingPlatform, videoID: String, startedAt: Date = .now) {
        self.platform = platform
        self.videoID = videoID
        self.startedAt = startedAt
    }

    /// Forward the official YouTube IFrame API events from this sample's player.
    public mutating func receiveYouTubeState(_ state: Int) {
        guard platform == .youTube else { return }
        receiveState(state)
    }

    /// Forward repeated getCurrentTime() values while the sample plays.
    public mutating func receiveYouTubePosition(_ seconds: Double, at time: ContinuousClock.Instant = .now) {
        guard platform == .youTube else { return }
        receivePosition(seconds, at: time)
    }

    public mutating func receiveYouTubeError(_ code: Int) {
        guard platform == .youTube, !result.status.isFinished else { return }
        result = .measured(.playerError(code: code))
    }

    public mutating func receiveYouTubeAutoplayBlocked() {
        guard platform == .youTube, !result.status.isFinished else { return }
        result = .measured(.autoplayBlocked)
    }

    /// The host must verify that the message comes from this sample's iframe before forwarding it.
    public mutating func receiveTikTokMessage(_ data: Data, origin: String, at time: ContinuousClock.Instant = .now) {
        guard platform == .tikTok, !result.status.isFinished, origin == "https://www.tiktok.com",
              let message = try? JSONDecoder().decode(TikTokMessage.self, from: data), message.isFromPlayer else { return }
        switch message.event {
        case .state(let state): receiveState(state)
        case .position(let seconds): receivePosition(seconds, at: time)
        case .error(let code):
            result = .measured(code == 3002 ? .autoplayBlocked : .playerError(code: code))
        case .ignored: break
        }
    }

    public mutating func timeout() {
        guard !result.status.isFinished else { return }
        result = .unavailable(.init(.timedOut))
    }

    public mutating func cancel() {
        guard !result.status.isFinished else { return }
        result = .cancelled
    }

    private mutating func receiveState(_ state: Int) {
        guard !result.status.isFinished else { return }
        playing = state == 1
        if !playing { firstPosition = nil }
    }

    private mutating func receivePosition(_ seconds: Double, at time: ContinuousClock.Instant) {
        guard !result.status.isFinished, playing, seconds.isFinite, seconds >= 0 else { return }
        guard let first = firstPosition else {
            firstPosition = (seconds, time)
            return
        }
        guard time > first.at else { return }
        let advance = seconds - first.seconds
        let duration = first.at.duration(to: time).components
        let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        if advance < 0 || advance > elapsed * 2 + 0.25 {
            // A seek or player reset does not count toward the observed advance.
            firstPosition = (seconds, time)
        } else if advance >= 0.75, elapsed >= 0.5 {
            result = .measured(.played)
        }
    }

    private struct TikTokMessage: Decodable {
        enum Event {
            case state(Int), position(Double), error(Int), ignored
        }

        struct Position: Decodable { let currentTime: Double }
        struct PlayerError: Decodable { let errorCode: Int }

        let isFromPlayer: Bool
        let event: Event

        private enum CodingKeys: String, CodingKey {
            case isFromPlayer = "x-tiktok-player"
            case type, value
        }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            isFromPlayer = try fields.decode(Bool.self, forKey: .isFromPlayer)
            switch try fields.decode(String.self, forKey: .type) {
            case "onStateChange":
                event = .state(try fields.decode(Int.self, forKey: .value))
            case "onCurrentTime":
                event = .position(try fields.decode(Position.self, forKey: .value).currentTime)
            case "onPlayerError":
                event = .error(try fields.decode(PlayerError.self, forKey: .value).errorCode)
            default:
                event = .ignored
            }
        }
    }
}
