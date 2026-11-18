import Foundation
import NodeSeekCore

/// `QualityStreamingService` behind the Core contract the screen uses.
public struct LiveStreamingChecker: StreamingChecking {
    private let injected: QualityStreamingService?
    /// One session for the app's life: screens may create this checker on every render.
    private static let shared = QualityStreamingService()
    private var service: QualityStreamingService { injected ?? Self.shared }

    public init() { injected = nil }
    init(service: QualityStreamingService) { injected = service }

    public var platforms: [StreamingPlatform] { StreamingPlatform.allCases }
    public var youTubeSampleVideoID: String { service.playbackCheck(for: .youTube)?.videoID ?? "" }

    public func run() -> AsyncStream<[StreamingSampleCheck]> {
        let service = service, platforms = platforms
        return AsyncStream { continuation in
            let task = Task {
                continuation.yield(platforms.map { StreamingSampleCheck(platform: $0, result: .running(.init())) })
                let observations = await service.run()
                if !Task.isCancelled { continuation.yield(observations.map(Self.check)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func playbackCheck(for platform: StreamingPlatform) -> (any StreamingPlaybackChecking)? {
        service.playbackCheck(for: QualityStreamingPlatform(platform)).map(LivePlaybackCheck.init)
    }

    public func checkYouTubeRegion(videoID: String, countryCode: String, apiKey: String) async -> YouTubeRegionCheck {
        let observation = await service.checkYouTubeRegion(videoID: videoID, countryCode: countryCode, apiKey: apiKey)
        return YouTubeRegionCheck(videoID: observation.videoID, countryCode: observation.countryCode,
                                  queriedAt: observation.queriedAt, result: observation.result.map { YouTubeRegionRule(rawValue: $0.rawValue) ?? .undetermined })
    }

    static func check(_ observation: QualityStreamingObservation) -> StreamingSampleCheck {
        StreamingSampleCheck(
            platform: StreamingPlatform(observation.platform), sampleTitle: observation.sampleTitle, endpoint: observation.endpoint,
            queriedAt: observation.queriedAt, httpStatus: observation.httpStatus,
            family: observation.connectionFamily.map { $0 == .ipv4 ? .v4 : .v6 },
            result: observation.result.map(StreamingEvidence.init))
    }
}

/// Wraps the client's playback interpreter so the screen can forward player events without knowing its type.
struct LivePlaybackCheck: StreamingPlaybackChecking {
    private var check: QualityStreamingPlaybackCheck

    init(_ check: QualityStreamingPlaybackCheck) { self.check = check }

    var platform: StreamingPlatform { StreamingPlatform(check.platform) }
    var videoID: String { check.videoID }
    var isSample: Bool { false }
    var result: QualityResult<StreamingPlaybackOutcome> {
        check.result.map { outcome in
            switch outcome {
            case .played: .played
            case .autoplayBlocked: .autoplayBlocked
            case .playerError(let code): .playerError(code: code)
            }
        }
    }

    mutating func receive(_ event: StreamingPlaybackEvent) {
        switch event {
        case .youTubeState(let state): check.receiveYouTubeState(state)
        case .youTubePosition(let seconds): check.receiveYouTubePosition(seconds)
        case .youTubeError(let code): check.receiveYouTubeError(code)
        case .youTubeAutoplayBlocked: check.receiveYouTubeAutoplayBlocked()
        case .tikTokMessage(let data, let origin): check.receiveTikTokMessage(data, origin: origin)
        case .timeout: check.timeout()
        case .cancel: check.cancel()
        case .sampleFinished: break
        }
    }
}

private extension QualityResult {
    func map<Other>(_ transform: (Value) -> Other) -> QualityResult<Other> {
        switch self {
        case .pending: .pending
        case .running(let progress): .running(progress)
        case .measured(let value): .measured(transform(value))
        case .failed(let issue): .failed(issue)
        case .unavailable(let issue): .unavailable(issue)
        case .cancelled: .cancelled
        case .notIncluded: .notIncluded
        }
    }
}

private extension StreamingPlatform {
    init(_ platform: QualityStreamingPlatform) {
        switch platform {
        case .netflix: self = .netflix
        case .disneyPlus: self = .disneyPlus
        case .primeVideo: self = .primeVideo
        case .youTube: self = .youTube
        case .tikTok: self = .tikTok
        }
    }
}

private extension QualityStreamingPlatform {
    init(_ platform: StreamingPlatform) {
        switch platform {
        case .netflix: self = .netflix
        case .disneyPlus: self = .disneyPlus
        case .primeVideo: self = .primeVideo
        case .youTube: self = .youTube
        case .tikTok: self = .tikTok
        }
    }
}

private extension StreamingEvidence {
    init(_ evidence: QualityStreamingObservation.Evidence) {
        switch evidence {
        case .titlePage: self = .titlePage
        case .embedMetadata: self = .embedMetadata
        case .authenticationRequired: self = .authenticationRequired
        case .legallyRestricted: self = .legallyRestricted
        case .redirected: self = .redirected
        case .undetermined: self = .undetermined
        }
    }
}
