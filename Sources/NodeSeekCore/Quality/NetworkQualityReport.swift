import Foundation

/// The steps of a network check, in the order they run and are listed.
public enum NetworkQualityStep: String, Sendable, Codable, CaseIterable, Identifiable {
    // First release
    case speed, ipv4, ipv6
    // Advanced
    case routes, nat, mailPort, reputation, services

    public var id: String { rawValue }
    public static let basic: [Self] = [.speed, .ipv4, .ipv6]
    public static let advanced: [Self] = [.routes, .nat, .mailPort, .reputation, .services]
}

/// One network check. The service sends a fresh snapshot after every change and the UI draws the latest.
public struct NetworkQualityReport: Sendable, Equatable, Codable {
    public var startedAt: Date
    public var finishedAt: Date?
    public var network: NetworkContext
    public var speed: QualityResult<SpeedMeasurement>
    public var ipv4: QualityResult<IPEgress>
    public var ipv6: QualityResult<IPEgress>
    public var routes: QualityResult<[RouteTrace]>
    public var nat: QualityResult<NATObservation>
    public var mailPort: QualityResult<PortProbe>
    public var reputation: QualityResult<[ReputationRecord]>
    public var services: QualityResult<[ServiceProbe]>

    public init(
        startedAt: Date, finishedAt: Date? = nil, network: NetworkContext,
        speed: QualityResult<SpeedMeasurement> = .pending,
        ipv4: QualityResult<IPEgress> = .pending, ipv6: QualityResult<IPEgress> = .pending,
        routes: QualityResult<[RouteTrace]> = .notIncluded, nat: QualityResult<NATObservation> = .notIncluded,
        mailPort: QualityResult<PortProbe> = .notIncluded, reputation: QualityResult<[ReputationRecord]> = .notIncluded,
        services: QualityResult<[ServiceProbe]> = .notIncluded
    ) {
        self.startedAt = startedAt; self.finishedAt = finishedAt; self.network = network
        self.speed = speed; self.ipv4 = ipv4; self.ipv6 = ipv6; self.routes = routes; self.nat = nat
        self.mailPort = mailPort; self.reputation = reputation; self.services = services
    }

    public func status(of step: NetworkQualityStep) -> QualityStatus {
        switch step {
        case .speed: speed.status
        case .ipv4: ipv4.status
        case .ipv6: ipv6.status
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
            case .speed: return speed.value.map { $0.downloadMbps == nil || $0.uploadMbps == nil } ?? false
            case .ipv4: return ipv4.value?.ownerIssue != nil
            case .ipv6: return ipv6.value?.ownerIssue != nil
            case .routes: return routes.value?.contains { $0.issue != nil } ?? false
            case .reputation: return reputation.value?.contains { $0.issue != nil } ?? false
            case .nat: return nat.value?.issue != nil
            case .mailPort, .services: return false
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
        copy.speed = speed.cancellingUnfinished; copy.ipv4 = ipv4.cancellingUnfinished; copy.ipv6 = ipv6.cancellingUnfinished
        copy.routes = routes.cancellingUnfinished; copy.nat = nat.cancellingUnfinished; copy.mailPort = mailPort.cancellingUnfinished
        copy.reputation = reputation.cancellingUnfinished; copy.services = services.cancellingUnfinished
        copy.finishedAt = copy.finishedAt ?? date
        return copy
    }

    /// Resets `steps` to pending so a retry runs them again and keeps everything else.
    public func resetting(_ steps: Set<NetworkQualityStep>) -> Self {
        var copy = self
        for step in steps {
            switch step {
            case .speed: copy.speed = .pending
            case .ipv4: copy.ipv4 = .pending
            case .ipv6: copy.ipv6 = .pending
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
    /// Median round trip while the line is idle.
    public var latencyMs: Double?
    /// Mean difference between consecutive latency samples.
    public var jitterMs: Double?
    public var latencySamples: Int
    public var bytesTransferred: Int64
    public var issues: [QualityIssue]

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

public enum ReputationVerdict: String, Sendable, Codable { case clean, low, medium, high, unknown }

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

public enum ServiceOutcome: String, Sendable, Codable { case reachable, regionRestricted, timedOut, undetermined }

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
    public var id: String { name }

    public init(name: String, outcome: ServiceOutcome, basis: ServiceBasis, region: String? = nil) {
        self.name = name; self.outcome = outcome; self.basis = basis; self.region = region
    }
}
