import Foundation

public enum QualityIPFamily: String, CaseIterable, Codable, Sendable {
    case ipv4, ipv6
}

public enum QualityCheck<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case pending
    case running
    case measured(Value)
    case unavailable(QualityIssue)
    case cancelled
}

public enum QualityIssue: Error, Codable, Equatable, Sendable {
    case offline
    case cancelled
    case networkChanged
    case timedOut
    case hostUnreachable
    case httpStatus(Int)
    case invalidResponse
    case wrongAddressFamily
    case insufficientSamples
    case transportError(Int)
    case unsupportedDevice
    case unsupportedMeasurement
    case alreadyRunning
    case prerequisiteFailed
    case fileError
}

public struct NetworkQualityReport: Codable, Equatable, Identifiable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case running
        case completed
        case cancelled
        case interrupted(QualityIssue)
    }

    public enum Step: String, CaseIterable, Codable, Sendable {
        case ipv4, ipv6, latency, download, upload
    }

    public enum Network: String, Codable, Sendable {
        case wifi, cellular, ethernet, other, offline, unknown
    }

    public let id: UUID
    public let startedAt: Date
    public internal(set) var finishedAt: Date?
    public internal(set) var state: State = .running
    public internal(set) var currentStep: Step?
    public internal(set) var completedStepCount = 0
    public internal(set) var network: Network = .unknown
    public internal(set) var ipv4: QualityCheck<QualityPublicIP> = .pending
    public internal(set) var ipv6: QualityCheck<QualityPublicIP> = .pending
    public internal(set) var latency: QualityCheck<QualityLatency> = .pending
    public internal(set) var download: QualityCheck<QualityBandwidth> = .pending
    public internal(set) var upload: QualityCheck<QualityBandwidth> = .pending

    init(id: UUID = UUID(), startedAt: Date = .now) {
        self.id = id
        self.startedAt = startedAt
    }
}

public struct QualitySource: Codable, Equatable, Sendable {
    public let provider: String
    public let endpoint: URL
    public let checkedAt: Date
}

public struct QualityPublicIP: Codable, Equatable, Sendable {
    public let address: String
    public let source: QualitySource
    public let attributionSource: QualitySource?
    public let attribution: QualityCheck<QualityIPAttribution>
}

public struct QualityIPAttribution: Codable, Equatable, Sendable {
    public let countryCode: String?
    public let region: String?
    public let city: String?
    public let asn: String?
    public let networkName: String?
}

public struct QualityLatency: Codable, Equatable, Sendable {
    public let source: QualitySource
    public let samples: [QualityLatencySample]

    public var milliseconds: Double? {
        let values = samples.compactMap(\.milliseconds).sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    public var jitterMilliseconds: Double? {
        let differences = zip(samples, samples.dropFirst()).compactMap { first, second -> Double? in
            guard let left = first.milliseconds, let right = second.milliseconds, first.node == second.node,
                  first.connectionFamily == second.connectionFamily else {
                return nil
            }
            return abs(left - right)
        }
        guard !differences.isEmpty else { return nil }
        return differences.reduce(0, +) / Double(differences.count)
    }
}

public struct QualityLatencySample: Codable, Equatable, Sendable {
    public let checkedAt: Date
    public let node: String?
    public let milliseconds: Double?
    public let issue: QualityIssue?
    public internal(set) var connectionFamily: QualityIPFamily? = nil
}

public struct QualityBandwidth: Codable, Equatable, Sendable {
    public let source: QualitySource
    public let samples: [QualityTransferSample]

    public var isEstimate: Bool {
        !samples.contains { ($0.seconds ?? 0) >= 0.25 }
    }

    public var megabitsPerSecond: Double? {
        let largestSuccessfulSize = samples.filter { $0.seconds != nil }.map(\.bytes).max()
        let estimate = isEstimate
        let comparable = samples.compactMap { sample -> Double? in
            guard let seconds = sample.seconds, seconds > 0 else { return nil }
            guard estimate ? sample.bytes == largestSuccessfulSize : seconds >= 0.25 else { return nil }
            return Double(sample.bytes) * 8 / seconds / 1_000_000
        }.sorted()
        guard !comparable.isEmpty else { return nil }
        let index = Double(comparable.count - 1) * 0.9
        let lower = Int(index.rounded(.down))
        let upper = Int(index.rounded(.up))
        return comparable[lower] + (comparable[upper] - comparable[lower]) * (index - Double(lower))
    }
}

public struct QualityTransferSample: Codable, Equatable, Sendable {
    public let checkedAt: Date
    public let node: String?
    public let bytes: Int
    public let seconds: Double?
    public let issue: QualityIssue?
    public internal(set) var connectionFamily: QualityIPFamily? = nil
}
