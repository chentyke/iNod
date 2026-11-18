import Foundation

public enum DeviceBenchmarkStep: String, Sendable, Codable, CaseIterable, Identifiable {
    case cpuSingle, cpuMulti, storageSequential, storageRandom
    public var id: String { rawValue }
}

/// Mirrors `ProcessInfo.ThermalState`, which is not Codable.
public enum ThermalLevel: String, Sendable, Codable, Comparable {
    case nominal, fair, serious, critical
    private var rank: Int { switch self { case .nominal: 0; case .fair: 1; case .serious: 2; case .critical: 3 } }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public struct DeviceInfo: Sendable, Equatable, Codable {
    /// Marketing name when known ("iPhone 17 Pro"), otherwise the model identifier.
    public var model: String
    public var systemVersion: String
    public var processorCount: Int

    public init(model: String, systemVersion: String, processorCount: Int) {
        self.model = model; self.systemVersion = systemVersion; self.processorCount = processorCount
    }
}

public struct CPUScore: Sendable, Equatable, Codable {
    /// Fixed workload iterations per second; higher is faster. Only comparable within the same app version.
    public var score: Int
    public var threads: Int
    public var duration: TimeInterval

    public init(score: Int, threads: Int, duration: TimeInterval) { self.score = score; self.threads = threads; self.duration = duration }
}

public struct StorageThroughput: Sendable, Equatable, Codable {
    public var readMBps: Double
    public var writeMBps: Double
    /// Random tests report operations per second; sequential ones leave it nil.
    public var readIOPS: Int?
    public var writeIOPS: Int?
    public var blockSize: Int
    public var fileBytes: Int64

    public init(readMBps: Double, writeMBps: Double, readIOPS: Int? = nil, writeIOPS: Int? = nil, blockSize: Int, fileBytes: Int64) {
        self.readMBps = readMBps; self.writeMBps = writeMBps; self.readIOPS = readIOPS; self.writeIOPS = writeIOPS
        self.blockSize = blockSize; self.fileBytes = fileBytes
    }
}

public struct DeviceBenchmarkReport: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var finishedAt: Date?
    public var device: DeviceInfo
    /// Benchmark version; scores from different versions are not compared.
    public var method: String
    public var thermalAtStart: ThermalLevel
    public var thermalAtEnd: ThermalLevel?
    public var lowPowerMode: Bool?
    public var cleanupIssue: QualityIssue?
    public var cpuSingle: QualityResult<CPUScore>
    public var cpuMulti: QualityResult<CPUScore>
    public var storageSequential: QualityResult<StorageThroughput>
    public var storageRandom: QualityResult<StorageThroughput>

    public init(id: UUID = UUID(), startedAt: Date, finishedAt: Date? = nil, device: DeviceInfo, method: String,
                thermalAtStart: ThermalLevel, thermalAtEnd: ThermalLevel? = nil,
                cpuSingle: QualityResult<CPUScore> = .pending, cpuMulti: QualityResult<CPUScore> = .pending,
                storageSequential: QualityResult<StorageThroughput> = .pending, storageRandom: QualityResult<StorageThroughput> = .pending) {
        self.id = id; self.startedAt = startedAt; self.finishedAt = finishedAt; self.device = device; self.method = method
        self.thermalAtStart = thermalAtStart; self.thermalAtEnd = thermalAtEnd; self.cpuSingle = cpuSingle; self.cpuMulti = cpuMulti
        self.storageSequential = storageSequential; self.storageRandom = storageRandom
    }

    public func status(of step: DeviceBenchmarkStep) -> QualityStatus {
        switch step {
        case .cpuSingle: cpuSingle.status
        case .cpuMulti: cpuMulti.status
        case .storageSequential: storageSequential.status
        case .storageRandom: storageRandom.status
        }
    }
    public var isFinished: Bool { DeviceBenchmarkStep.allCases.allSatisfy { status(of: $0).isFinished } }
    /// Every step measured, so the run can be compared with earlier ones.
    public var isComplete: Bool { cleanupIssue == nil && DeviceBenchmarkStep.allCases.allSatisfy { status(of: $0) == .measured } }
    public var runningStep: DeviceBenchmarkStep? {
        DeviceBenchmarkStep.allCases.first { if case .running = status(of: $0) { true } else { false } }
    }
    /// The run got hot enough that the system may have slowed the processor.
    public var mayBeThrottled: Bool { max(thermalAtStart, thermalAtEnd ?? thermalAtStart) >= .serious }

    public func cancellingUnfinished(at date: Date = .now) -> Self {
        var copy = self
        copy.cpuSingle = cpuSingle.cancellingUnfinished; copy.cpuMulti = cpuMulti.cancellingUnfinished
        copy.storageSequential = storageSequential.cancellingUnfinished; copy.storageRandom = storageRandom.cancellingUnfinished
        copy.finishedAt = copy.finishedAt ?? date
        return copy
    }
}
