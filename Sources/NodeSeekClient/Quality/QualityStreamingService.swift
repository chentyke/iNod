import Foundation
import NodeSeekCore

public enum QualityStreamingPlatform: String, CaseIterable, Codable, Sendable {
    case netflix, disneyPlus, primeVideo, youTube, tikTok
}

public struct QualityStreamingObservation: Codable, Equatable, Sendable {
    public enum Evidence: Codable, Equatable, Sendable {
        case titlePage
        case embedMetadata
        case authenticationRequired
        case legallyRestricted
        case redirected
        case undetermined
    }

    public let platform: QualityStreamingPlatform
    public let sampleTitle: String
    public let endpoint: URL
    public let queriedAt: Date
    public let httpStatus: Int?
    public let connectionFamily: QualityIPFamily?
    public let result: QualityResult<Evidence>
}

public struct QualityYouTubeRegionObservation: Codable, Equatable, Sendable {
    public enum Rule: String, Codable, Sendable {
        case allowed, blocked, noPublishedRule, undetermined
    }

    public let videoID: String
    public let countryCode: String
    public let queriedAt: Date
    public let result: QualityResult<Rule>
}

/// Checks public title or embed metadata over the device's current connection.
public struct QualityStreamingService: Sendable {
    private let send: QualityHTTP.Request

    public init() {
        let session = QualityHTTP.makeSession()
        self.init { try await QualityHTTP.request(using: session, request: $0, upload: $1) }
    }

    init(send: @escaping QualityHTTP.Request) {
        self.send = send
    }

    public func run() async -> [QualityStreamingObservation] {
        await withTaskGroup(of: (Int, QualityStreamingObservation).self) { group in
            for (index, platform) in QualityStreamingPlatform.allCases.enumerated() {
                group.addTask { (index, await check(platform)) }
            }
            var observations: [(Int, QualityStreamingObservation)] = []
            for await observation in group { observations.append(observation) }
            return observations.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Creates a result collector for the matching sample in a visible official player.
    public func playbackCheck(for platform: QualityStreamingPlatform) -> QualityStreamingPlaybackCheck? {
        let sample = Sample(platform)
        guard sample.isEmbed else { return nil }
        return QualityStreamingPlaybackCheck(platform: platform, videoID: sample.id)
    }

    /// Checks a published rule for the supplied country. This does not determine the viewer's location.
    public func checkYouTubeRegion(
        videoID: String, countryCode: String, apiKey: String
    ) async -> QualityYouTubeRegionObservation {
        let country = countryCode.uppercased()
        let queriedAt = Date.now
        let result: QualityResult<QualityYouTubeRegionObservation.Rule>
        if videoID.wholeMatch(of: /[A-Za-z0-9_-]{11}/) == nil ||
            country.wholeMatch(of: /[A-Z]{2}/) == nil || apiKey.isEmpty {
            result = .unavailable(.init(.notSupported))
        } else {
            let url = URL(string: "https://www.googleapis.com/youtube/v3/videos")!.appending(queryItems: [
                .init(name: "id", value: videoID),
                .init(name: "part", value: "contentDetails"),
                .init(name: "fields", value: "items(id,contentDetails(regionRestriction))")
            ])
            do {
                try Task.checkCancellation()
                var request = URLRequest(url: url, timeoutInterval: 6)
                request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
                let response = try await send(request, nil)
                try Task.checkCancellation()
                try response.validateStatus()
                let payload = try JSONDecoder().decode(YouTubeVideoList.self, from: response.body)
                result = .measured(payload.rule(videoID: videoID, country: country))
            } catch {
                result = Task.isCancelled ? .cancelled : .failed(LiveNetworkQualityTester.issue(QualityIssue(error: error)))
            }
        }
        return QualityYouTubeRegionObservation(videoID: videoID, countryCode: country, queriedAt: queriedAt, result: result)
    }

    private struct YouTubeVideoList: Decodable {
        struct Item: Decodable {
            struct Content: Decodable {
                struct Restriction: Decodable {
                    let allowed: [String]?
                    let blocked: [String]?
                }

                let regionRestriction: Restriction?
            }

            let id: String
            let contentDetails: Content
        }

        let items: [Item]

        func rule(videoID: String, country: String) -> QualityYouTubeRegionObservation.Rule {
            guard let item = items.first(where: { $0.id == videoID }) else { return .undetermined }
            guard let restriction = item.contentDetails.regionRestriction else { return .noPublishedRule }
            switch (restriction.allowed, restriction.blocked) {
            case (let allowed?, nil): return allowed.contains(country) ? .allowed : .blocked
            case (nil, let blocked?): return blocked.contains(country) ? .blocked : .allowed
            default: return .undetermined
            }
        }
    }

    private func check(_ platform: QualityStreamingPlatform) async -> QualityStreamingObservation {
        let sample = Sample(platform)
        let queriedAt = Date.now
        let result: QualityResult<QualityStreamingObservation.Evidence>
        var httpStatus: Int?
        var family: QualityIPFamily?
        do {
            try Task.checkCancellation()
            var request = URLRequest(url: sample.endpoint, timeoutInterval: 6)
            request.setValue(sample.isEmbed ? "application/json" : "text/html", forHTTPHeaderField: "Accept")
            let response = try await send(request, nil)
            try Task.checkCancellation()
            httpStatus = response.statusCode
            family = response.connectionFamily
            switch response.statusCode {
            case 200:
                result = .measured(sample.evidence(in: response.body))
            case 401:
                result = .measured(.authenticationRequired)
            case 451:
                result = .measured(.legallyRestricted)
            case 300...399:
                result = .measured(.redirected)
            case 403, 404:
                // Missing, unembeddable and blocked requests can use the same status.
                result = .measured(.undetermined)
            default:
                result = .failed(LiveNetworkQualityTester.issue(.httpStatus(response.statusCode)))
            }
        } catch {
            result = Task.isCancelled ? .cancelled : .failed(LiveNetworkQualityTester.issue(QualityIssue(error: error)))
        }
        return QualityStreamingObservation(platform: platform, sampleTitle: sample.title, endpoint: sample.endpoint,
                                           queriedAt: queriedAt, httpStatus: httpStatus, connectionFamily: family, result: result)
    }

    private struct Sample {
        let platform: QualityStreamingPlatform
        let title: String
        let id: String
        let endpoint: URL

        var isEmbed: Bool { platform == .youTube || platform == .tikTok }

        init(_ platform: QualityStreamingPlatform) {
            self.platform = platform
            switch platform {
            case .netflix:
                title = "Squid Game"; id = "81040344"
                endpoint = URL(string: "https://www.netflix.com/title/\(id)")!
            case .disneyPlus:
                title = "Soul"; id = "entity-5f055dc5-cc07-43f2-839e-bf073b16a823"
                endpoint = URL(string: "https://www.disneyplus.com/browse/\(id)")!
            case .primeVideo:
                title = "Fallout (Season 1)"; id = "0HAQAA7JM43QWX0H6GUD3IOF70"
                endpoint = URL(string: "https://www.primevideo.com/detail/\(id)")!
            case .youTube:
                title = "Embedded Web Player Customization"; id = "M7lc1UVf-VE"
                endpoint = URL(string: "https://www.youtube.com/oembed")!.appending(queryItems: [
                    .init(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
                    .init(name: "format", value: "json")
                ])
            case .tikTok:
                title = "TikTok embed sample"; id = "6718335390845095173"
                endpoint = URL(string: "https://www.tiktok.com/oembed")!.appending(queryItems: [
                    .init(name: "url", value: "https://www.tiktok.com/@scout2015/video/\(id)")
                ])
            }
        }

        func evidence(in data: Data) -> QualityStreamingObservation.Evidence {
            if isEmbed {
                guard let payload = try? JSONDecoder().decode(Embed.self, from: data),
                      payload.type == "video", embedMatches(payload) else { return .undetermined }
                return .embedMetadata
            }
            let page = String(decoding: data, as: UTF8.self)
            guard let canonical = Self.canonicalURL(in: page),
                  canonical.scheme == "https", canonical.host() == endpoint.host(),
                  canonical.lastPathComponent == id else { return .undetermined }
            return .titlePage
        }

        private func embedMatches(_ embed: Embed) -> Bool {
            switch platform {
            case .youTube: embed.provider == "YouTube" && embed.html.contains("https://www.youtube.com/embed/\(id)?")
            case .tikTok: embed.provider == "TikTok" && embed.productID == id
            default: false
            }
        }

        private static func canonicalURL(in page: String) -> URL? {
            guard let headEnd = page.range(of: "</head", options: .caseInsensitive) else { return nil }
            let head = String(page[..<headEnd.lowerBound])
            let link = /(?i)<link\s+[^>]*>/
            let canonical = /(?i)\brel\s*=\s*["']canonical["']/
            let href = /(?i)\bhref\s*=\s*["']([^"']+)["']/
            for match in head.matches(of: link) where match.output.contains(canonical) {
                if let attribute = match.output.firstMatch(of: href) { return URL(string: String(attribute.1)) }
            }
            return nil
        }

        private struct Embed: Decodable {
            let type: String
            let provider: String
            let html: String
            let productID: String?

            enum CodingKeys: String, CodingKey {
                case type, html
                case provider = "provider_name"
                case productID = "embed_product_id"
            }
        }
    }
}
