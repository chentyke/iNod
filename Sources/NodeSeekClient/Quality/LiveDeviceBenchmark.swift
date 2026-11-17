import NodeSeekCore

public struct LiveDeviceBenchmark: DeviceBenchmarking {
    public init() {}

    public var scratchBytes: Int64 { Int64(HardwareQualityService.storageBytes) }

    public func run() -> AsyncStream<DeviceBenchmarkReport> {
        AsyncStream { continuation in
            let task = Task {
                let final = await HardwareQualityService.run { continuation.yield(Self.report($0)) }
                continuation.yield(Self.report(final))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func report(_ raw: HardwareQualityReport) -> DeviceBenchmarkReport {
        let device = DeviceInfo(model: raw.deviceModel, systemVersion: raw.operatingSystem, processorCount: raw.processorCount)
        var result = DeviceBenchmarkReport(
            id: raw.id, startedAt: raw.startedAt, finishedAt: raw.finishedAt, device: device, method: "iNod Bench 1",
            thermalAtStart: thermal(raw.initialThermalState), thermalAtEnd: raw.finalThermalState.map(thermal)
        )
        result.lowPowerMode = raw.lowPowerMode
        if case .unavailable(let issue) = raw.state {
            let problem = LiveNetworkQualityTester.issue(issue)
            result.cpuSingle = .unavailable(problem)
            result.cpuMulti = .unavailable(problem)
            result.storageSequential = .unavailable(problem)
            result.storageRandom = .unavailable(problem)
            return result
        }
        result.cpuSingle = cpu(raw.cpu, threads: 1)
        result.cpuMulti = cpu(raw.cpuMulti, threads: raw.processorCount)
        result.storageSequential = storage(read: raw.read, write: raw.write, blockSize: HardwareQualityService.blockBytes, random: false)
        result.storageRandom = storage(read: raw.randomRead, write: raw.randomWrite, blockSize: HardwareQualityService.randomBlockBytes, random: true)
        if raw.cleanupIssue != nil { result.cleanupIssue = .init(.other, detail: "测试文件未能删除") }
        if case .cancelled = raw.state { return result.cancellingUnfinished() }
        return result
    }

    private static func cpu(_ result: QualityCheck<HardwareQualityMeasurement>, threads: Int) -> QualityResult<CPUScore> {
        switch result {
        case .pending: .pending
        case .running: .running(.init())
        case .measured(let value): .measured(.init(score: Int(value.mebibytesPerSecond), threads: threads, duration: value.seconds))
        case .unavailable(let problem): .failed(LiveNetworkQualityTester.issue(problem))
        case .cancelled: .cancelled
        }
    }

    private static func storage(
        read: QualityCheck<HardwareQualityMeasurement>, write: QualityCheck<HardwareQualityMeasurement>, blockSize: Int, random: Bool
    ) -> QualityResult<StorageThroughput> {
        if let read = read.value, let write = write.value {
            return .measured(.init(
                readMBps: Double(read.bytes) / read.seconds / 1_000_000, writeMBps: Double(write.bytes) / write.seconds / 1_000_000,
                readIOPS: random ? Int(Double(read.bytes / blockSize) / read.seconds) : nil,
                writeIOPS: random ? Int(Double(write.bytes / blockSize) / write.seconds) : nil,
                blockSize: blockSize, fileBytes: Int64(HardwareQualityService.storageBytes)
            ))
        }
        if let problem = write.issue ?? read.issue { return .failed(LiveNetworkQualityTester.issue(problem)) }
        if read == .cancelled || write == .cancelled { return .cancelled }
        if write == .running || read == .running || write.value != nil { return .running(.init(fraction: write.value == nil ? 0 : 0.5)) }
        return .pending
    }

    private static func thermal(_ state: HardwareQualityReport.Thermal) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair, .unknown: .fair
        case .serious: .serious
        case .critical: .critical
        }
    }
}
