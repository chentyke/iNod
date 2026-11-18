import Foundation
import NodeSeekCore

public struct QualityIPLookup<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let provider: String
    public let queriedAt: Date
    public let result: QualityResult<Value>
}

public struct QualityIPDetails: Codable, Equatable, Sendable {
    public let family: IPFamily
    public let routing: QualityIPLookup<QualityBGPRouting>
    public let risk: QualityIPLookup<QualityIPRisk>
}

public enum QualityBGPRouting: Codable, Equatable, Sendable {
    case announced(prefix: String, originASNs: [UInt32])
    /// RIPE RIS had no matching announcement at the time of the lookup.
    case noAnnouncementObserved
}

public struct QualityIPRisk: Codable, Equatable, Sendable {
    /// IPQuery's 0...100 policy score. Its value is not an abuse probability.
    public let score: Int?
    /// A false flag means this source found no match. Nil means the source omitted the field.
    public let isMobile: Bool?
    public let isVPN: Bool?
    public let isTor: Bool?
    public let isProxy: Bool?
    public let isDatacenter: Bool?
}

/// A separate lookup for the addresses measured by the base network check.
public struct QualityIPDetailsService: Sendable {
    private let send: QualityHTTP.Request

    public init() {
        let session = QualityHTTP.makeSession()
        self.init { try await QualityHTTP.request(using: session, request: $0, upload: $1) }
    }

    init(send: @escaping QualityHTTP.Request) {
        self.send = send
    }

    public func run(for report: NodeSeekCore.NetworkQualityReport) async -> [QualityIPDetails] {
        async let ipv4 = details(for: report.ipv4.value, family: .v4)
        async let ipv6 = details(for: report.ipv6.value, family: .v6)
        return await [ipv4, ipv6].compactMap { $0 }
    }

    private func details(for egress: IPEgress?, family: IPFamily) async -> QualityIPDetails? {
        guard let egress, egress.family == family,
              let bytes = QualityReputation.addressBytes(egress.address),
              bytes.count == (family == .v4 ? 4 : 16) else { return nil }

        var routesURL = URLComponents(url: URL(string: "https://stat.ripe.net/data/network-info/data.json")!,
                                     resolvingAgainstBaseURL: false)!
        routesURL.queryItems = [.init(name: "resource", value: egress.address), .init(name: "sourceapp", value: "iNod")]
        let riskURL = URL(string: "https://api.ipquery.io")!.appending(path: egress.address, directoryHint: .notDirectory)

        async let routing = lookup("RIPEstat", url: routesURL.url!) { body in
            let payload = try JSONDecoder().decode(RoutingPayload.self, from: body)
            return try payload.routing(for: bytes)
        }
        async let risk = lookup("IPQuery", url: riskURL) { body in
            let payload = try JSONDecoder().decode(RiskPayload.self, from: body)
            guard QualityReputation.addressBytes(payload.ip) == bytes else { throw QualityIssue.invalidResponse }
            return try payload.risk.observation()
        }
        return await QualityIPDetails(family: family, routing: routing, risk: risk)
    }

    private func lookup<Value: Codable & Equatable & Sendable>(
        _ provider: String, url: URL, decode: @Sendable (Data) throws -> Value
    ) async -> QualityIPLookup<Value> {
        let queriedAt = Date.now
        let result: QualityResult<Value>
        do {
            try Task.checkCancellation()
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response = try await send(request, nil)
            try Task.checkCancellation()
            try response.validateStatus()
            result = .measured(try decode(response.body))
        } catch {
            result = Task.isCancelled ? .cancelled : .failed(LiveNetworkQualityTester.issue(QualityIssue(error: error)))
        }
        return QualityIPLookup(provider: provider, queriedAt: queriedAt, result: result)
    }

    private struct RoutingPayload: Decodable {
        struct Observation: Decodable {
            let prefix: String
            let asns: [String]
        }

        let status: String
        let data: Observation

        func routing(for address: [UInt8]) throws -> QualityBGPRouting {
            guard status == "ok" else { throw QualityIssue.invalidResponse }
            if data.prefix.isEmpty, data.asns.isEmpty { return .noAnnouncementObserved }

            let asns = data.asns.compactMap(UInt32.init)
            guard QualityReputation.matches(cidr: data.prefix, address: address) == true,
                  !asns.isEmpty, asns.count == data.asns.count, !asns.contains(0) else {
                throw QualityIssue.invalidResponse
            }
            return .announced(prefix: data.prefix, originASNs: Set(asns).sorted())
        }
    }

    private struct RiskPayload: Decodable {
        struct Fields: Decodable {
            let riskScore: Int?
            let isMobile: Bool?
            let isVPN: Bool?
            let isTor: Bool?
            let isProxy: Bool?
            let isDatacenter: Bool?

            enum CodingKeys: String, CodingKey {
                case riskScore = "risk_score"
                case isMobile = "is_mobile"
                case isVPN = "is_vpn"
                case isTor = "is_tor"
                case isProxy = "is_proxy"
                case isDatacenter = "is_datacenter"
            }

            func observation() throws -> QualityIPRisk {
                if let riskScore, !(0...100).contains(riskScore) { throw QualityIssue.invalidResponse }
                guard riskScore != nil || [isMobile, isVPN, isTor, isProxy, isDatacenter].contains(where: { $0 != nil }) else {
                    throw QualityIssue.invalidResponse
                }
                return QualityIPRisk(score: riskScore, isMobile: isMobile, isVPN: isVPN, isTor: isTor,
                                     isProxy: isProxy, isDatacenter: isDatacenter)
            }
        }

        let ip: String
        let risk: Fields
    }
}
