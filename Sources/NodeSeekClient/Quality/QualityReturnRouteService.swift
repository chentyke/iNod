import Foundation
import Network
import NodeSeekCore

public struct QualityReturnRoute: Codable, Equatable, Sendable {
    public struct Trace: Codable, Equatable, Sendable {
        public let probeCity: String
        public let hops: [RouteHop]
        /// Whether a hop from the requested public destination itself replied.
        public let reachedTarget: Bool
    }

    public let carrier: ChinaCarrier
    public let probeASN: UInt32
    public let family: IPFamily
    public let startedAt: Date
    public let result: QualityResult<Trace>
}

/// A measurement from carrier-side Globalping probes to one publicly shareable address.
public struct QualityReturnRouteService: Sendable {
    private static let endpoint = URL(string: "https://api.globalping.io/v1/measurements")!
    private static let sources: [(carrier: ChinaCarrier, asn: UInt32)] = [(.telecom, 4134), (.unicom, 4837), (.mobile, 9808)]
    private let send: QualityHTTP.Request

    public init() {
        let session = QualityHTTP.makeSession()
        self.init { try await QualityHTTP.request(using: session, request: $0, upload: $1) }
    }

    init(send: @escaping QualityHTTP.Request) {
        self.send = send
    }

    /// Globalping measurements are public. Use only a destination address the caller may publish.
    /// The base network check does not invoke this service automatically.
    public func trace(toPublicTarget target: IPEgress) async -> [QualityReturnRoute] {
        let startedAt = Date.now
        var results: [UInt32: QualityResult<QualityReturnRoute.Trace>] = [:]
        var missing: QualityResult<QualityReturnRoute.Trace>
        if let address = Self.targetBytes(target) {
            do {
                results = try await measure(target, bytes: address)
                missing = .unavailable(.init(.serviceUnavailable, detail: "没有对应运营商的节点回应"))
            } catch {
                missing = Task.isCancelled ? .cancelled : .failed(LiveNetworkQualityTester.issue(QualityIssue(error: error)))
            }
        } else {
            missing = .unavailable(.init(.notSupported, detail: "需要可公开探测的公网地址"))
        }

        return Self.sources.map { source in
            return QualityReturnRoute(carrier: source.carrier, probeASN: source.asn, family: target.family,
                                      startedAt: startedAt, result: results[source.asn] ?? missing)
        }
    }

    private func measure(_ target: IPEgress, bytes: Data) async throws -> [UInt32: QualityResult<QualityReturnRoute.Trace>] {
        try Task.checkCancellation()
        var request = Self.request(Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(StartRequest(
            target: target.address, locations: Self.sources.map { .init(asn: $0.asn) }
        ))
        let response = try await send(request, nil)
        try response.validateStatus()
        let id = try JSONDecoder().decode(StartResponse.self, from: response.body).id
        guard !id.isEmpty, id.count <= 128, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw QualityIssue.invalidResponse
        }
        let url = Self.endpoint.appending(path: id, directoryHint: .notDirectory)
        var completed: [UInt32: QualityResult<QualityReturnRoute.Trace>] = [:]
        let deadline = ContinuousClock.now.advanced(by: .seconds(16))
        do {
            repeat {
                try Task.checkCancellation()
                let update = try await send(Self.request(url), nil)
                try update.validateStatus()
                let measurement = try JSONDecoder().decode(Measurement.self, from: update.body)
                guard measurement.type == "traceroute", Self.addressBytes(measurement.target, family: target.family) == bytes else {
                    throw QualityIssue.invalidResponse
                }
                for sample in measurement.results where sample.probe.country == "CN" &&
                    Self.sources.contains(where: { $0.asn == sample.probe.asn }) {
                    if let result = sample.observation(target: bytes, family: target.family) { completed[sample.probe.asn] = result }
                }
                if measurement.status == .finished { return completed }
                try await Task.sleep(for: .seconds(1))
            } while ContinuousClock.now < deadline
            throw QualityIssue.timedOut
        } catch {
            let remaining: QualityResult<QualityReturnRoute.Trace> = Task.isCancelled
                ? .cancelled : .failed(LiveNetworkQualityTester.issue(QualityIssue(error: error)))
            for source in Self.sources where completed[source.asn] == nil { completed[source.asn] = remaining }
            return completed
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func targetBytes(_ target: IPEgress) -> Data? {
        let bytes = addressBytes(target.address, family: target.family)
        switch target.family {
        case .v4:
            return QualityRoutes.isPublic(target.address) ? bytes : nil
        case .v6:
            guard let first = bytes?.first, first & 0xe0 == 0x20 else { return nil }
            return bytes
        }
    }

    private static func addressBytes(_ text: String, family: IPFamily) -> Data? {
        switch family {
        case .v4: IPv4Address(text)?.rawValue
        case .v6: IPv6Address(text)?.rawValue
        }
    }

    private struct StartRequest: Encodable {
        struct Location: Encodable {
            let asn: UInt32
            let country = "CN"
            let limit = 1
        }

        struct Options: Encodable {
            let `protocol` = "ICMP"
        }

        let type = "traceroute"
        let timeout = 10
        let target: String
        let locations: [Location]
        let measurementOptions = Options()
    }

    private struct StartResponse: Decodable {
        let id: String
    }

    private struct Measurement: Decodable {
        enum Status: String, Decodable {
            case inProgress = "in-progress"
            case finished
        }

        let type: String
        let status: Status
        let target: String
        let results: [Sample]
    }

    private struct Sample: Decodable {
        struct Probe: Decodable {
            let asn: UInt32
            let city: String
            let country: String
        }

        struct Result: Decodable {
            struct Hop: Decodable {
                struct Timing: Decodable { let rtt: Double }
                let resolvedAddress: String?
                let timings: [Timing]
            }

            let status: String
            let resolvedAddress: String?
            let hops: [Hop]?
        }

        let probe: Probe
        let result: Result

        func observation(target: Data, family: IPFamily) -> QualityResult<QualityReturnRoute.Trace>? {
            switch result.status {
            case "in-progress": return nil
            case "finished":
                guard let resolved = result.resolvedAddress, let hops = result.hops,
                      addressBytes(resolved, family: family) == target else {
                    return .failed(.init(.serviceUnavailable, detail: "节点返回的目标与请求不一致"))
                }
                let route = hops.enumerated().map { index, hop in
                    let times = hop.timings.map(\.rtt).filter { $0.isFinite && $0 >= 0 }
                    let latency = times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
                    return RouteHop(index: index + 1, address: hop.resolvedAddress, rttMs: latency)
                }
                let reached = route.contains { hop in
                    guard let address = hop.address, hop.rttMs != nil else { return false }
                    return addressBytes(address, family: family) == target
                }
                return .measured(.init(probeCity: probe.city, hops: route, reachedTarget: reached))
            default: return .failed(.init(.serviceUnavailable, detail: "远端节点未能完成路由测试"))
            }
        }
    }
}
