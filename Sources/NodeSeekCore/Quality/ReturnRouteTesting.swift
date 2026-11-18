import Foundation

// The three-carrier return route trace: probes inside China trace toward an address the reader chose.
// The measurement service publishes the target and the results, so the reader starts it on its own,
// never as part of the network check.

/// A public address the remote probes can trace to.
public struct ReturnRouteTarget: Sendable, Equatable, Codable {
    public var family: IPFamily
    public var address: String

    public enum Problem: Error, Equatable {
        case empty, notAnAddress, notPublic

        /// Shown under the field. An empty field needs no explanation.
        public var message: String? {
            switch self {
            case .empty: nil
            case .notAnAddress: "不是有效的 IPv4 或 IPv6 地址。"
            case .notPublic: "这是内网或保留地址，远端节点无法访问。"
            }
        }
    }

    public init(family: IPFamily, address: String) { self.family = family; self.address = address }

    /// Accepts the same addresses the service measures: a public unicast IPv4, or an IPv6 in 2000::/3.
    public static func parse(_ text: String) -> Result<ReturnRouteTarget, Problem> {
        // Chinese keyboards put full-width punctuation next to the ASCII marks.
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "．", with: ".")
            .replacingOccurrences(of: "：", with: ":")
        guard !address.isEmpty else { return .failure(.empty) }
        if let bytes = bytes(address, family: .v4) {
            return isPublicV4(bytes) ? .success(.init(family: .v4, address: address)) : .failure(.notPublic)
        }
        if let bytes = bytes(address, family: .v6) {
            return bytes[0] & 0xe0 == 0x20 ? .success(.init(family: .v6, address: address)) : .failure(.notPublic)
        }
        return .failure(.notAnAddress)
    }

    private static func bytes(_ text: String, family: IPFamily) -> [UInt8]? {
        // Zone indexes and prefixes are not addresses a remote probe can reach.
        guard !text.contains("%"), !text.contains("/") else { return nil }
        var buffer = [UInt8](repeating: 0, count: family == .v4 ? 4 : 16)
        let parsed = text.withCString { inet_pton(family == .v4 ? AF_INET : AF_INET6, $0, &buffer) }
        return parsed == 1 ? buffer : nil
    }

    private static func isPublicV4(_ b: [UInt8]) -> Bool {
        b[0] != 0 && b[0] != 10 && b[0] != 127 && b[0] < 224 &&
            !(b[0] == 100 && (64...127).contains(b[1])) && !(b[0] == 169 && b[1] == 254) &&
            !(b[0] == 172 && (16...31).contains(b[1])) && !(b[0] == 192 && b[1] == 168)
    }
}

/// One carrier's trace toward the target.
public struct ReturnRoute: Sendable, Equatable, Codable, Identifiable {
    public struct Trace: Sendable, Equatable, Codable {
        /// As the measurement service names it, usually in English.
        public var probeCity: String
        /// A hop that never answered keeps its place, with no address.
        public var hops: [RouteHop]
        /// Whether the target itself replied.
        public var reachedTarget: Bool

        public init(probeCity: String, hops: [RouteHop], reachedTarget: Bool) {
            self.probeCity = probeCity; self.hops = hops; self.reachedTarget = reachedTarget
        }

        /// The round trip at the furthest hop that answered: the target's when it replied.
        public var lastLatencyMs: Double? { hops.last { $0.rttMs != nil }?.rttMs }
    }

    public var carrier: ChinaCarrier
    public var probeASN: UInt32
    public var target: ReturnRouteTarget
    public var startedAt: Date
    public var result: QualityResult<Trace>
    public var id: ChinaCarrier { carrier }

    public init(carrier: ChinaCarrier, probeASN: UInt32, target: ReturnRouteTarget, startedAt: Date, result: QualityResult<Trace>) {
        self.carrier = carrier; self.probeASN = probeASN; self.target = target; self.startedAt = startedAt; self.result = result
    }
}

/// The return route trace, as the UI calls it. Returns one entry per carrier, in telecom, unicom, mobile order;
/// a carrier without a probe or a result says why and the others still report. Cancelling the calling task
/// marks unfinished carriers `.cancelled`.
public protocol ReturnRouteTesting: Sendable {
    func trace(to target: ReturnRouteTarget) async -> [ReturnRoute]
}

/// Answers after a short wait with documentation addresses: telecom reaches the target, unicom reaches it past
/// two silent hops, mobile has no probe.
public struct SampleReturnRouteTester: ReturnRouteTesting {
    /// Seconds to wait is `2 * pace`; UI tests shorten it.
    public var pace: Double
    public init(pace: Double = 1) { self.pace = pace }

    public func trace(to target: ReturnRouteTarget) async -> [ReturnRoute] {
        let startedAt = Date.now
        let finished = (try? await Task.sleep(for: .milliseconds(Int(2_000 * pace)))) != nil
        return Self.routes(to: target, at: startedAt, cancelled: !finished)
    }

    public static func routes(to target: ReturnRouteTarget, at date: Date = Date(timeIntervalSince1970: 1_795_420_800),
                              cancelled: Bool = false) -> [ReturnRoute] {
        let v4 = target.family == .v4
        func hops(_ prefix: String, count: Int, silentAt silent: Set<Int>, base: Double) -> [RouteHop] {
            (1...count).map { index in
                if silent.contains(index) { return RouteHop(index: index, address: nil) }
                let address = index == count ? target.address
                    : index == 1 ? (v4 ? "10.0.0.1" : "fd00::1")
                    : v4 ? "\(prefix).\(index * 6)" : "2001:db8:\(prefix.split(separator: ".").last ?? "0")::\(index)"
                return RouteHop(index: index, address: address, rttMs: base * Double(index) / Double(count) + 0.6)
            }
        }
        let results: [(ChinaCarrier, UInt32, QualityResult<ReturnRoute.Trace>)] = [
            (.telecom, 4134, .measured(.init(probeCity: "Shanghai", hops: hops("192.0.2", count: 11, silentAt: [], base: 152), reachedTarget: true))),
            (.unicom, 4837, .measured(.init(probeCity: "Beijing", hops: hops("198.51.100", count: 13, silentAt: [4, 5], base: 186), reachedTarget: true))),
            (.mobile, 9808, .unavailable(.init(.serviceUnavailable, detail: "没有对应运营商的节点回应"))),
        ]
        return results.map { carrier, asn, result in
            ReturnRoute(carrier: carrier, probeASN: asn, target: target, startedAt: date, result: cancelled ? .cancelled : result)
        }
    }
}
