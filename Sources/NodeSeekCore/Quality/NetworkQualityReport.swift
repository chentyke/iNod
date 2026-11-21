import Foundation

/// The steps of a network check, in the order they run and are listed.
public enum NetworkQualityStep: String, Sendable, Codable, CaseIterable, Identifiable {
    // First release
    case speed, ipv4, ipv6
    // Advanced
    case ipDetails, routes, nat, mailPort, reputation, services

    public var id: String { rawValue }
    public static let basic: [Self] = [.speed, .ipv4, .ipv6]
    public static let advanced: [Self] = [.ipDetails, .routes, .nat, .mailPort, .reputation, .services]
}

/// One network check. The service sends a fresh snapshot after every change and the UI draws the latest.
public struct NetworkQualityReport: Sendable, Equatable, Codable {
    public var startedAt: Date
    public var finishedAt: Date?
    public var network: NetworkContext
    public var speed: QualityResult<SpeedMeasurement>
    public var partialSpeed: SpeedMeasurement?
    public var ipv4: QualityResult<IPEgress>
    public var ipv6: QualityResult<IPEgress>
    /// BGP route and usage type for each measured address.
    public var ipDetails: QualityResult<[IPProfile]>
    public var routes: QualityResult<[RouteTrace]>
    public var nat: QualityResult<NATObservation>
    public var mailPort: QualityResult<PortProbe>
    public var reputation: QualityResult<[ReputationRecord]>
    public var services: QualityResult<[ServiceProbe]>

    public init(
        startedAt: Date, finishedAt: Date? = nil, network: NetworkContext,
        speed: QualityResult<SpeedMeasurement> = .pending,
        ipv4: QualityResult<IPEgress> = .pending, ipv6: QualityResult<IPEgress> = .pending,
        ipDetails: QualityResult<[IPProfile]> = .notIncluded,
        routes: QualityResult<[RouteTrace]> = .notIncluded, nat: QualityResult<NATObservation> = .notIncluded,
        mailPort: QualityResult<PortProbe> = .notIncluded, reputation: QualityResult<[ReputationRecord]> = .notIncluded,
        services: QualityResult<[ServiceProbe]> = .notIncluded
    ) {
        self.startedAt = startedAt; self.finishedAt = finishedAt; self.network = network
        self.speed = speed; self.ipv4 = ipv4; self.ipv6 = ipv6; self.ipDetails = ipDetails; self.routes = routes; self.nat = nat
        self.mailPort = mailPort; self.reputation = reputation; self.services = services
    }

    public func status(of step: NetworkQualityStep) -> QualityStatus {
        switch step {
        case .speed: speed.status
        case .ipv4: ipv4.status
        case .ipv6: ipv6.status
        case .ipDetails: ipDetails.status
        case .routes: routes.status
        case .nat: nat.status
        case .mailPort: mailPort.status
        case .reputation: reputation.status
        case .services: services.status
        }
    }

    /// Steps worth running again: failed or cancelled ones, and measured ones with a missing part
    /// (one speed direction, the address owner, one route or one reputation source).
    public var retryableSteps: [NetworkQualityStep] {
        includedSteps.filter { step in
            if status(of: step).canRetry { return true }
            switch step {
            case .speed: return speed.value?.needsRetry == true
            case .ipv4: return ipv4.value?.ownerIssue != nil
            case .ipv6: return ipv6.value?.ownerIssue != nil
            case .ipDetails: return ipDetails.value?.contains { $0.hasFailure } ?? false
            case .routes: return routes.value?.contains { $0.issue != nil } ?? false
            case .reputation: return reputation.value?.contains { $0.issue != nil } ?? false
            case .nat: return nat.value?.issue != nil
            case .mailPort: return false
            case .services: return services.value?.contains { $0.issue != nil } ?? false
            }
        }
    }

    /// The steps this run covers, in order.
    public var includedSteps: [NetworkQualityStep] {
        NetworkQualityStep.allCases.filter { status(of: $0) != .notIncluded }
    }
    public var isFinished: Bool { includedSteps.allSatisfy { status(of: $0).isFinished } }
    public var runningStep: NetworkQualityStep? {
        includedSteps.first { if case .running = status(of: $0) { true } else { false } }
    }

    /// What the report keeps after the reader cancels: finished results, with every unfinished step marked cancelled.
    public func cancellingUnfinished(at date: Date = .now) -> Self {
        var copy = self
        copy.speed = partialSpeed.map { .measured($0) } ?? speed.cancellingUnfinished; copy.partialSpeed = nil
        copy.ipv4 = ipv4.cancellingUnfinished; copy.ipv6 = ipv6.cancellingUnfinished; copy.ipDetails = ipDetails.cancellingUnfinished
        copy.routes = routes.cancellingUnfinished; copy.nat = nat.cancellingUnfinished; copy.mailPort = mailPort.cancellingUnfinished
        copy.reputation = reputation.cancellingUnfinished; copy.services = services.cancellingUnfinished
        copy.finishedAt = copy.finishedAt ?? date
        return copy
    }

    /// If a retry stops before producing replacement results, keep the successful parts of the earlier run.
    public func keepingMeasurements(from previous: Self?) -> Self {
        guard let previous else { return self }
        var copy = self
        copy.ipv4 = ipv4.keepingAddress(from: previous.ipv4)
        copy.ipv6 = ipv6.keepingAddress(from: previous.ipv6)
        copy.routes = routes.keepingRecords(from: previous.routes, issue: \.issue)
        if copy.ipv4.value?.address == previous.ipv4.value?.address, copy.ipv6.value?.address == previous.ipv6.value?.address {
            copy.reputation = reputation.keepingRecords(from: previous.reputation, issue: \.issue)
        }
        copy.services = services.keepingRecords(from: previous.services, issue: \.issue)
        return copy
    }

    /// Resets `steps` to pending so a retry runs them again and keeps everything else.
    public func resetting(_ steps: Set<NetworkQualityStep>) -> Self {
        var copy = self
        for step in steps {
            switch step {
            case .speed: copy.speed = .pending; copy.partialSpeed = nil
            case .ipv4: copy.ipv4 = .pending
            case .ipv6: copy.ipv6 = .pending
            case .ipDetails: copy.ipDetails = .pending
            case .routes: copy.routes = .pending
            case .nat: copy.nat = .pending
            case .mailPort: copy.mailPort = .pending
            case .reputation: copy.reputation = .pending
            case .services: copy.services = .pending
            }
        }
        copy.finishedAt = nil
        return copy
    }
    public mutating func setRunning(_ step: NetworkQualityStep, _ progress: QualityProgress) {
        switch step {
        case .speed: speed = .running(progress)
        case .ipv4: ipv4 = .running(progress)
        case .ipv6: ipv6 = .running(progress)
        case .ipDetails: ipDetails = .running(progress)
        case .routes: routes = .running(progress)
        case .nat: nat = .running(progress)
        case .mailPort: mailPort = .running(progress)
        case .reputation: reputation = .running(progress)
        case .services: services = .running(progress)
        }
    }

    public mutating func setFailed(_ step: NetworkQualityStep, _ issue: QualityIssue) {
        switch step {
        case .speed:
            if var measured = partialSpeed {
                measured.issues.append(issue)
                speed = .measured(measured)
                partialSpeed = nil
            } else { speed = .failed(issue) }
        case .ipv4: ipv4 = .failed(issue)
        case .ipv6: ipv6 = .failed(issue)
        case .ipDetails: ipDetails = .failed(issue)
        case .routes: routes = .failed(issue)
        case .nat: nat = .failed(issue)
        case .mailPort: mailPort = .failed(issue)
        case .reputation: reputation = .failed(issue)
        case .services: services = .failed(issue)
        }
    }

}

private extension QualityResult {
    func keepingAddress(from previous: Self) -> Self where Value == IPEgress {
        guard var address = previous.value, address.ownerIssue != nil else { return self }
        switch self {
        case .failed(let issue):
            address.ownerIssue = issue
            return .measured(address)
        case .cancelled: return previous
        default: return self
        }
    }

    func keepingRecords<Record>(from previous: Self, issue: WritableKeyPath<Record, QualityIssue?>) -> Self where Value == [Record] {
        guard let records = previous.value, records.contains(where: { $0[keyPath: issue] == nil }),
              records.contains(where: { $0[keyPath: issue] != nil }) else { return self }
        switch self {
        case .failed(let failure):
            var kept = records
            for index in kept.indices where kept[index][keyPath: issue] != nil {
                kept[index][keyPath: issue] = failure
            }
            return .measured(kept)
        case .cancelled: return previous
        default: return self
        }
    }
}

// MARK: - Speed

public struct SpeedServer: Sendable, Equatable, Codable {
    /// Who runs the test service, e.g. "Cloudflare".
    public var provider: String
    /// Where the chosen node is, e.g. "东京".
    public var location: String
    public var host: String?

    public init(provider: String, location: String, host: String? = nil) {
        self.provider = provider; self.location = location; self.host = host
    }
}

public struct SpeedMeasurement: Sendable, Equatable, Codable {
    public var server: SpeedServer
    /// nil when that direction did not finish; `issues` says why.
    public var downloadMbps: Double?
    public var uploadMbps: Double?
    public var downloadIsEstimate: Bool?
    public var uploadIsEstimate: Bool?
    /// Median round trip while the line is idle.
    public var latencyMs: Double?
    /// Mean difference between consecutive latency samples.
    public var jitterMs: Double?
    public var latencySamples: Int
    public var bytesTransferred: Int64
    public var issues: [QualityIssue]

    package var needsRetry: Bool {
        downloadMbps == nil || uploadMbps == nil || latencyMs == nil || jitterMs == nil
    }

    public init(server: SpeedServer, downloadMbps: Double?, uploadMbps: Double?, latencyMs: Double?, jitterMs: Double?,
                latencySamples: Int, bytesTransferred: Int64, issues: [QualityIssue] = []) {
        self.server = server; self.downloadMbps = downloadMbps; self.uploadMbps = uploadMbps; self.latencyMs = latencyMs
        self.jitterMs = jitterMs; self.latencySamples = latencySamples; self.bytesTransferred = bytesTransferred; self.issues = issues
    }
}

// MARK: - Public address

public struct IPOwner: Sendable, Equatable, Codable {
    public var country: String?
    /// ISO 3166 code, for the flag.
    public var countryCode: String?
    public var region: String?
    public var city: String?
    public var asn: Int?
    public var organization: String?
    /// The lookup service the answer came from.
    public var source: String

    public init(country: String?, countryCode: String? = nil, region: String? = nil, city: String? = nil,
                asn: Int? = nil, organization: String? = nil, source: String) {
        self.country = country; self.countryCode = countryCode; self.region = region; self.city = city
        self.asn = asn; self.organization = organization; self.source = source
    }
}

/// The public address the phone reaches the internet from, for one address family.
public struct IPEgress: Sendable, Equatable, Codable {
    public var family: IPFamily
    public var address: String
    /// The endpoint that echoed the address back.
    public var echoSource: String
    public var owner: IPOwner?
    /// Why `owner` is missing when the address itself was found.
    public var ownerIssue: QualityIssue?
    public var queriedAt: Date

    public init(family: IPFamily, address: String, echoSource: String, owner: IPOwner?, ownerIssue: QualityIssue? = nil, queriedAt: Date) {
        self.family = family; self.address = address; self.echoSource = echoSource
        self.owner = owner; self.ownerIssue = ownerIssue; self.queriedAt = queriedAt
    }
}

// MARK: - IP type and routing

/// One lookup about a public address, with the source that answered it.
public struct IPLookup<Value: Sendable & Equatable & Codable>: Sendable, Equatable, Codable {
    public var source: String
    public var queriedAt: Date
    public var result: QualityResult<Value>

    public init(source: String, queriedAt: Date, result: QualityResult<Value>) {
        self.source = source; self.queriedAt = queriedAt; self.result = result
    }
}

/// The BGP announcement covering an address, as a route collector saw it.
public struct BGPRoute: Sendable, Equatable, Codable {
    /// nil when the collector saw no announcement for the address.
    public var prefix: String?
    public var originASNs: [Int]

    public init(prefix: String?, originASNs: [Int] = []) { self.prefix = prefix; self.originASNs = originASNs }
}

public enum IPUsageTag: String, Sendable, Codable, CaseIterable { case datacenter, vpn, proxy, tor, mobile }

/// How one source classifies an address. Its score is the source's own scale, not an abuse probability.
public struct IPUsage: Sendable, Equatable, Codable {
    public var score: Int?
    /// Tags the source matched.
    public var tags: [IPUsageTag]
    /// Tags the source left out of its answer, so they are neither matched nor ruled out.
    public var unreported: [IPUsageTag]

    public init(score: Int?, tags: [IPUsageTag], unreported: [IPUsageTag] = []) {
        self.score = score; self.tags = tags; self.unreported = unreported
    }
}

/// Routing and usage type for one measured address; each lookup can succeed or fail on its own.
public struct IPProfile: Sendable, Equatable, Codable, Identifiable {
    public var family: IPFamily
    public var route: IPLookup<BGPRoute>
    public var usage: IPLookup<IPUsage>
    public var id: String { family.rawValue }
    public var hasFailure: Bool { !route.result.isMeasured || !usage.result.isMeasured }

    public init(family: IPFamily, route: IPLookup<BGPRoute>, usage: IPLookup<IPUsage>) {
        self.family = family; self.route = route; self.usage = usage
    }
}

// MARK: - Routes

public enum ChinaCarrier: String, Sendable, Codable, CaseIterable { case telecom, unicom, mobile }

public struct RouteHop: Sendable, Equatable, Codable, Identifiable {
    public var index: Int
    /// nil when the hop never answered.
    public var address: String?
    public var rttMs: Double?
    /// "AS4134 中国电信", when the hop could be identified.
    public var owner: String?
    public var id: Int { index }

    public init(index: Int, address: String?, rttMs: Double? = nil, owner: String? = nil) {
        self.index = index; self.address = address; self.rttMs = rttMs; self.owner = owner
    }
}

public struct RouteTrace: Sendable, Equatable, Codable, Identifiable {
    public var carrier: ChinaCarrier
    public var city: String
    public var family: IPFamily
    public var target: String
    public var sent: Int
    public var received: Int
    public var averageLatencyMs: Double?
    public var hops: [RouteHop]
    /// Set when this target could not be tested; the other targets still report.
    public var issue: QualityIssue?
    public var id: String { "\(carrier.rawValue)-\(city)-\(family.rawValue)" }
    public var lossRate: Double? { sent > 0 ? Double(sent - received) / Double(sent) : nil }

    public init(carrier: ChinaCarrier, city: String, family: IPFamily, target: String, sent: Int, received: Int,
                averageLatencyMs: Double?, hops: [RouteHop], issue: QualityIssue? = nil) {
        self.carrier = carrier; self.city = city; self.family = family; self.target = target; self.sent = sent
        self.received = received; self.averageLatencyMs = averageLatencyMs; self.hops = hops; self.issue = issue
    }
}

// MARK: - NAT and ports

public enum NATType: String, Sendable, Codable {
    case openInternet, fullCone, restrictedCone, portRestrictedCone, symmetric, udpBlocked, undetermined
    case endpointIndependent, addressDependent, addressAndPortDependent
}

public struct NATObservation: Sendable, Equatable, Codable {
    public var type: NATType
    public var server: String
    /// The public address and port the server saw, e.g. "203.0.113.24:51820".
    public var mappedEndpoint: String?
    /// Why the type is `.undetermined`.
    public var issue: QualityIssue?

    public init(type: NATType, server: String, mappedEndpoint: String? = nil, issue: QualityIssue? = nil) {
        self.type = type; self.server = server; self.mappedEndpoint = mappedEndpoint; self.issue = issue
    }
}

public enum PortOutcome: String, Sendable, Codable { case open, refused, timedOut, undetermined }

public struct PortProbe: Sendable, Equatable, Codable {
    public var target: String
    public var port: Int
    public var outcome: PortOutcome

    public init(target: String, port: Int, outcome: PortOutcome) { self.target = target; self.port = port; self.outcome = outcome }
}

// MARK: - Reputation

public enum ReputationVerdict: String, Sendable, Codable { case clean, low, medium, high, unknown, listed, notListed }

public struct ReputationRecord: Sendable, Equatable, Codable, Identifiable {
    public var source: String
    public var family: IPFamily
    public var verdict: ReputationVerdict
    /// The source's own words, e.g. "Hosting" or "风险分 12".
    public var label: String?
    public var queriedAt: Date
    /// Set when this source failed; other sources still report.
    public var issue: QualityIssue?
    public var id: String { "\(source)-\(family.rawValue)" }

    public init(source: String, family: IPFamily, verdict: ReputationVerdict, label: String? = nil, queriedAt: Date, issue: QualityIssue? = nil) {
        self.source = source; self.family = family; self.verdict = verdict; self.label = label; self.queriedAt = queriedAt; self.issue = issue
    }
}

// MARK: - Services

public enum ServiceOutcome: String, Sendable, Codable { case reachable, regionRestricted, timedOut, undetermined, redirected, legallyRestricted }

/// What a service check actually asked, so the report never claims more than it tested.
public enum ServiceBasis: String, Sendable, Codable {
    /// Only loaded the website.
    case webPage
    /// Asked the service which region it serves.
    case regionCheck
}

public struct ServiceProbe: Sendable, Equatable, Codable, Identifiable {
    public var name: String
    public var outcome: ServiceOutcome
    public var basis: ServiceBasis
    /// The region the service reported, when `basis` is `.regionCheck`.
    public var region: String?
    public var endpoint: URL?
    public var issue: QualityIssue?
    public var httpStatus: Int?
    public var id: String { name }

    public init(name: String, outcome: ServiceOutcome, basis: ServiceBasis, region: String? = nil,
                endpoint: URL? = nil, issue: QualityIssue? = nil, httpStatus: Int? = nil) {
        self.name = name; self.outcome = outcome; self.basis = basis; self.region = region
        self.endpoint = endpoint; self.issue = issue; self.httpStatus = httpStatus
    }
}
