import Foundation

public struct HardwareQualityReport: Codable, Equatable, Identifiable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case running
        case completed
        case cancelled
        case unavailable(QualityIssue)
    }

    public enum Step: String, CaseIterable, Codable, Sendable {
        case cpu, write, read
    }

    public enum Thermal: String, Codable, Sendable {
        case nominal, fair, serious, critical, unknown
    }

    public let id: UUID
    public let startedAt: Date
    public let deviceModel: String
    public let operatingSystem: String
    public let lowPowerMode: Bool
    public let initialThermalState: Thermal
    public internal(set) var finalThermalState: Thermal?
    public internal(set) var finishedAt: Date?
    public internal(set) var state: State = .running
    public internal(set) var currentStep: Step?
    public internal(set) var cpu: QualityCheck<HardwareQualityMeasurement> = .pending
    public internal(set) var write: QualityCheck<HardwareQualityMeasurement> = .pending
    public internal(set) var read: QualityCheck<HardwareQualityMeasurement> = .pending
    public internal(set) var cleanupIssue: QualityIssue?
}

public struct HardwareQualityMeasurement: Codable, Equatable, Sendable {
    public let bytes: Int
    public let seconds: Double
    public let thermalState: HardwareQualityReport.Thermal

    public var mebibytesPerSecond: Double { Double(bytes) / 1_048_576 / seconds }
}
