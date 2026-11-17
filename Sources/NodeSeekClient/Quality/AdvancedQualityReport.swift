import Foundation

public struct AdvancedQualityReport: Codable, Equatable, Sendable {
    public let basicReportID: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let services: [QualityServiceAccess]
    public let ipReputation: [QualityIPReputation]
    public let mail: QualityMailAccess
    public let nat: [QualityNATReport]
    public let routes: [QualityRouteReport]
}

public struct QualityServiceAccess: Codable, Equatable, Sendable {
    public enum Result: Codable, Equatable, Sendable {
        case webpageAccessible(httpStatus: Int)
        case redirected(httpStatus: Int)
        case legallyRestricted(httpStatus: Int)
    }

    public let source: QualitySource
    public let result: QualityCheck<Result>
}

public struct QualityIPReputation: Codable, Equatable, Sendable {
    public enum Verdict: Codable, Equatable, Sendable {
        case listed(reference: String?)
        case notListed
    }

    public let source: QualitySource
    public let family: QualityIPFamily
    public let result: QualityCheck<Verdict>
}

public struct QualityMailAccess: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable {
        case connected, refused, timedOut
    }

    public let host: String
    public let port: UInt16
    public let checkedAt: Date
    public let result: QualityCheck<Result>
}

public struct QualityNATReport: Codable, Equatable, Sendable {
    public enum Mapping: String, Codable, Sendable {
        case endpointIndependent, addressDependent, addressAndPortDependent
    }

    public struct Sample: Codable, Equatable, Sendable {
        public let target: String
        public let publicAddress: String
        public let publicPort: UInt16
    }

    public let host: String
    public let port: UInt16
    public let checkedAt: Date
    public let result: QualityCheck<Mapping>
    public let samples: [Sample]
}

public struct QualityRouteReport: Codable, Equatable, Sendable {
    public struct Hop: Codable, Equatable, Sendable {
        public let number: Int
        public let address: String?
        public let milliseconds: Double?
        public internal(set) var network: QualityIPAttribution? = nil
    }

    public let host: String
    public let city: String
    public let carrier: String
    public let family: QualityIPFamily
    public let checkedAt: Date
    public let address: String?
    public let sent: Int
    public let received: Int
    public internal(set) var hops: [Hop]
    public let reachedDestination: Bool
    public let issue: QualityIssue?

    public var lossPercent: Double? {
        guard sent > 0 else { return nil }
        return 100 * Double(sent - received) / Double(sent)
    }
}
