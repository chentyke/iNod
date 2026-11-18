import Foundation

// Streaming sample checks, as the UI sees them. The live service lives in NodeSeekClient; the screen only uses these.

public enum StreamingPlatform: String, CaseIterable, Codable, Sendable, Identifiable {
    case netflix, disneyPlus, primeVideo, youTube, tikTok

    public var id: Self { self }
    public var title: String {
        switch self {
        case .netflix: "Netflix"
        case .disneyPlus: "Disney+"
        case .primeVideo: "Prime Video"
        case .youTube: "YouTube"
        case .tikTok: "TikTok"
        }
    }
    /// Platforms whose sample can be tried in the official embedded player.
    public static let playable: [StreamingPlatform] = [.youTube, .tikTok]
}

/// What one platform returned for its public sample. Each case names only the information the request got back.
public enum StreamingEvidence: String, Codable, Sendable {
    case titlePage, embedMetadata, authenticationRequired, legallyRestricted, redirected, undetermined
}

public struct StreamingSampleCheck: Codable, Equatable, Sendable, Identifiable {
    public var platform: StreamingPlatform
    public var sampleTitle: String?
    public var endpoint: URL?
    public var queriedAt: Date?
    public var httpStatus: Int?
    public var family: IPFamily?
    public var result: QualityResult<StreamingEvidence>

    public var id: StreamingPlatform { platform }

    public init(platform: StreamingPlatform, sampleTitle: String? = nil, endpoint: URL? = nil, queriedAt: Date? = nil,
                httpStatus: Int? = nil, family: IPFamily? = nil, result: QualityResult<StreamingEvidence>) {
        self.platform = platform; self.sampleTitle = sampleTitle; self.endpoint = endpoint; self.queriedAt = queriedAt
        self.httpStatus = httpStatus; self.family = family; self.result = result
    }
}

public enum StreamingPlaybackOutcome: Codable, Equatable, Sendable {
    case played, autoplayBlocked, playerError(code: Int)
}

/// What the screen forwards from a visible official player, after checking where each message came from.
public enum StreamingPlaybackEvent: Sendable {
    case youTubeState(Int)
    case youTubePosition(Double)
    case youTubeError(Int)
    case youTubeAutoplayBlocked
    /// A raw message from the TikTok player iframe, with the origin the page reported.
    case tikTokMessage(Data, origin: String)
    case timeout
    case cancel
    /// The offline stand-in player finished its script.
    case sampleFinished
}

/// One attempt to play a sample in its official player.
public protocol StreamingPlaybackChecking: Sendable {
    var platform: StreamingPlatform { get }
    var videoID: String { get }
    var result: QualityResult<StreamingPlaybackOutcome> { get }
    /// True for offline samples: the screen shows a stand-in instead of loading the official player.
    var isSample: Bool { get }
    mutating func receive(_ event: StreamingPlaybackEvent)
}

public enum YouTubeRegionRule: String, Codable, Sendable {
    case allowed, blocked, noPublishedRule, undetermined
}

public struct YouTubeRegionCheck: Codable, Equatable, Sendable {
    public var videoID: String
    public var countryCode: String
    public var queriedAt: Date
    public var result: QualityResult<YouTubeRegionRule>

    public init(videoID: String, countryCode: String, queriedAt: Date, result: QualityResult<YouTubeRegionRule>) {
        self.videoID = videoID; self.countryCode = countryCode; self.queriedAt = queriedAt; self.result = result
    }

    /// The forms the YouTube Data API accepts; anything else is caught before a request is sent.
    public static func isValidVideoID(_ id: String) -> Bool { id.wholeMatch(of: /[A-Za-z0-9_-]{11}/) != nil }
    public static func isValidCountryCode(_ code: String) -> Bool { code.uppercased().wholeMatch(of: /[A-Z]{2}/) != nil }
}

/// The streaming checks, as the UI calls them.
///
/// `run` yields every platform's row after each change and finishes when all have finished. Cancel by cancelling the
/// iterating task; the screen marks unfinished rows cancelled itself.
public protocol StreamingChecking: Sendable {
    var platforms: [StreamingPlatform] { get }
    /// The sample the region form starts with.
    var youTubeSampleVideoID: String { get }
    func run() -> AsyncStream<[StreamingSampleCheck]>
    /// nil for platforms without an embeddable sample.
    func playbackCheck(for platform: StreamingPlatform) -> (any StreamingPlaybackChecking)?
    func checkYouTubeRegion(videoID: String, countryCode: String, apiKey: String) async -> YouTubeRegionCheck
}

public extension StreamingEvidence {
    /// Says which information came back, never that paid playback works.
    var title: String {
        switch self {
        case .titlePage: "片名页可访问"
        case .embedMetadata: "嵌入信息可取得"
        case .authenticationRequired: "需要登录"
        case .legallyRestricted: "法律限制（451）"
        case .redirected: "返回重定向"
        case .undetermined: "无法判断"
        }
    }
}

public extension StreamingPlaybackOutcome {
    var title: String {
        switch self {
        case .played: "已播放"
        case .autoplayBlocked: "自动播放被拦"
        case .playerError(let code): "播放器错误 \(code)"
        }
    }
}

public extension YouTubeRegionRule {
    var title: String {
        switch self {
        case .allowed: "规则允许"
        case .blocked: "规则限制"
        case .noPublishedRule: "未发布地区规则"
        case .undetermined: "无法判断"
        }
    }
}

// MARK: - Samples

/// Plays mixed sample results back for offline UI work and tests. Titles are the live service's samples.
public struct SampleStreamingChecker: StreamingChecking {
    public var pace: Double
    public init(pace: Double = 1) { self.pace = pace }

    public var platforms: [StreamingPlatform] { StreamingPlatform.allCases }
    public var youTubeSampleVideoID: String { "M7lc1UVf-VE" }

    public static func results(at date: Date = .now) -> [StreamingSampleCheck] {
        [
            .init(platform: .netflix, sampleTitle: "Squid Game", queriedAt: date, httpStatus: 200, family: .v4, result: .measured(.titlePage)),
            .init(platform: .disneyPlus, sampleTitle: "Soul", queriedAt: date, httpStatus: 403, family: .v4, result: .measured(.undetermined)),
            .init(platform: .primeVideo, sampleTitle: "Fallout (Season 1)", queriedAt: date, httpStatus: 302, family: .v4, result: .measured(.redirected)),
            .init(platform: .youTube, sampleTitle: "Embedded Web Player Customization", queriedAt: date, httpStatus: 200, family: .v6, result: .measured(.embedMetadata)),
            .init(platform: .tikTok, sampleTitle: "TikTok embed sample", queriedAt: date, result: .failed(.init(.timedOut))),
        ]
    }

    public func run() -> AsyncStream<[StreamingSampleCheck]> {
        let final = Self.results(), pace = pace
        return AsyncStream { continuation in
            let task = Task {
                var checks = final.map { StreamingSampleCheck(platform: $0.platform, sampleTitle: $0.sampleTitle, result: .running(.init())) }
                continuation.yield(checks)
                for index in checks.indices {
                    do { try await Task.sleep(for: .milliseconds(Int(400 * pace))) } catch { break }
                    checks[index] = final[index]
                    continuation.yield(checks)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func playbackCheck(for platform: StreamingPlatform) -> (any StreamingPlaybackChecking)? {
        switch platform {
        case .youTube: SamplePlaybackCheck(platform: .youTube, videoID: youTubeSampleVideoID, outcome: .played)
        case .tikTok: SamplePlaybackCheck(platform: .tikTok, videoID: "6718335390845095173", outcome: .autoplayBlocked)
        default: nil
        }
    }

    public func checkYouTubeRegion(videoID: String, countryCode: String, apiKey: String) async -> YouTubeRegionCheck {
        try? await Task.sleep(for: .milliseconds(Int(500 * pace)))
        let rule: YouTubeRegionRule = videoID == youTubeSampleVideoID ? .noPublishedRule : .undetermined
        return .init(videoID: videoID, countryCode: countryCode.uppercased(), queriedAt: .now,
                     result: Task.isCancelled ? .cancelled : .measured(rule))
    }
}

/// A scripted playback attempt: finishes with `outcome` when the stand-in player says so.
public struct SamplePlaybackCheck: StreamingPlaybackChecking {
    public let platform: StreamingPlatform
    public let videoID: String
    public let outcome: StreamingPlaybackOutcome
    public private(set) var result: QualityResult<StreamingPlaybackOutcome> = .running(.init())
    public var isSample: Bool { true }

    public init(platform: StreamingPlatform, videoID: String, outcome: StreamingPlaybackOutcome) {
        self.platform = platform; self.videoID = videoID; self.outcome = outcome
    }

    public mutating func receive(_ event: StreamingPlaybackEvent) {
        guard !result.status.isFinished else { return }
        switch event {
        case .sampleFinished: result = .measured(outcome)
        case .timeout: result = .unavailable(.init(.timedOut))
        case .cancel: result = .cancelled
        default: break
        }
    }
}
