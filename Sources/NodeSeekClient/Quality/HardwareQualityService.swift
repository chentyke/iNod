import CryptoKit
import Darwin
import Foundation

public actor HardwareQualityService {
    public static let cpuBytes = 128 * 1_048_576
    public static let storageBytes = 64 * 1_048_576
    static let blockBytes = 1_048_576
    static let randomBlockBytes = 4096
    private static let randomOperations = 4096
    private static let shared = HardwareQualityService()
    private var running = false

    private init() {}

    /// Measure SHA-256 and sequential and random file I/O on an iPhone. Cancel the calling task to stop.
    public static func run(
        onProgress: @escaping @Sendable (HardwareQualityReport) async -> Void = { _ in }
    ) async -> HardwareQualityReport {
        await shared.run(onProgress: onProgress)
    }

    private func run(onProgress: @escaping @Sendable (HardwareQualityReport) async -> Void) async -> HardwareQualityReport {
        let report = Self.makeReport()
        guard report.deviceModel.hasPrefix("iPhone") else { return Self.finish(report, state: .unavailable(.unsupportedDevice)) }
        guard !running else { return Self.finish(report, state: .unavailable(.alreadyRunning)) }
        running = true
        defer { running = false }
        let worker = Task.detached(priority: .userInitiated) {
            await Self.benchmark(report, in: FileManager.default.temporaryDirectory, onProgress: onProgress)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func benchmark(
        _ initial: HardwareQualityReport, in directory: URL,
        onProgress: @Sendable (HardwareQualityReport) async -> Void = { _ in }
    ) async -> HardwareQualityReport {
        var report = initial
        let file = directory.appending(path: "iNod-Quality-\(initial.id).tmp")
        var createdFile = false
        let cpuBlock = Data(repeating: 0xA5, count: blockBytes)
        if !Task.isCancelled {
            report.currentStep = .cpu
            report.cpu = .running
            await onProgress(report)
            report.cpu = measure(bytes: cpuBytes) { try hash(cpuBlock, iterations: cpuBytes / blockBytes) }
        }
        if !Task.isCancelled {
            report.currentStep = .cpuMulti
            report.cpuMulti = .running
            await onProgress(report)
            report.cpuMulti = await measureMulticore(cpuBlock, processors: report.processorCount)
        }
        let storageBlock = Task.isCancelled ? Data() : makeStorageBlock()
        if !Task.isCancelled {
            report.currentStep = .write
            report.write = .running
            await onProgress(report)
            report.write = measure(bytes: storageBytes) {
                try write(storageBlock, to: file, createdFile: &createdFile)
            }
        }
        if !Task.isCancelled {
            if case .measured = report.write {
                report.currentStep = .read
                report.read = .running
                await onProgress(report)
                report.read = measure(bytes: storageBytes) { try read(from: file) }
            } else {
                report.read = .unavailable(.prerequisiteFailed)
            }
        }
        if !Task.isCancelled {
            if case .measured = report.read {
                let block = Data(storageBlock.prefix(randomBlockBytes))
                report.currentStep = .randomWrite
                report.randomWrite = .running
                await onProgress(report)
                report.randomWrite = measure(bytes: randomBlockBytes * randomOperations) {
                    try randomAccess(file, writing: block)
                }
                if !Task.isCancelled, case .measured = report.randomWrite {
                    report.currentStep = .randomRead
                    report.randomRead = .running
                    await onProgress(report)
                    report.randomRead = measure(bytes: randomBlockBytes * randomOperations) {
                        try randomAccess(file, writing: nil)
                    }
                } else if !Task.isCancelled {
                    report.randomRead = .unavailable(.prerequisiteFailed)
                }
            } else {
                report.randomWrite = .unavailable(.prerequisiteFailed)
                report.randomRead = .unavailable(.prerequisiteFailed)
            }
        }
        if createdFile {
            do { try FileManager.default.removeItem(at: file) }
            catch { report.cleanupIssue = .fileError }
        }
        return finish(report, state: Task.isCancelled ? .cancelled : .completed)
    }

    static func makeReport() -> HardwareQualityReport {
        var info = utsname()
        let model = uname(&info) == 0 ? withUnsafeBytes(of: &info.machine) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        } : "unknown"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return HardwareQualityReport(
            id: UUID(), startedAt: .now, deviceModel: model,
            operatingSystem: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, initialThermalState: thermalState()
        )
    }

    private static func finish(_ initial: HardwareQualityReport, state: HardwareQualityReport.State) -> HardwareQualityReport {
        var report = initial
        report.state = state
        report.currentStep = nil
        report.finishedAt = .now
        report.finalThermalState = thermalState()
        return report
    }

    private static func thermalState() -> HardwareQualityReport.Thermal {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }

    private static func measure(bytes: Int, operation: () throws -> Void) -> QualityCheck<HardwareQualityMeasurement> {
        do {
            try Task.checkCancellation()
            let thermal = thermalState()
            let start = ContinuousClock.now
            try operation()
            return measurement(bytes: bytes, since: start, thermal: thermal)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .unavailable(.fileError)
        }
    }

    private static func measurement(
        bytes: Int, since start: ContinuousClock.Instant, thermal: HardwareQualityReport.Thermal
    ) -> QualityCheck<HardwareQualityMeasurement> {
        let elapsed = start.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        guard seconds > 0 else { return .unavailable(.insufficientSamples) }
        return .measured(.init(bytes: bytes, seconds: seconds, thermalState: thermal))
    }

    private static func hash(_ block: Data, iterations: Int) throws {
        for _ in 0..<iterations {
            try Task.checkCancellation()
            _ = SHA256.hash(data: block)
        }
    }

    private static func measureMulticore(_ block: Data, processors: Int) async -> QualityCheck<HardwareQualityMeasurement> {
        let iterations = cpuBytes / blockBytes
        let workers = min(max(1, processors), iterations)
        let thermal = thermalState()
        let start = ContinuousClock.now
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for worker in 0..<workers {
                    let count = iterations / workers + (worker < iterations % workers ? 1 : 0)
                    group.addTask { try hash(block, iterations: count) }
                }
                try await group.waitForAll()
            }
            try Task.checkCancellation()
            return measurement(bytes: cpuBytes, since: start, thermal: thermal)
        } catch { return .cancelled }
    }

    private static func makeStorageBlock() -> Data {
        var words = [UInt64](repeating: 0, count: blockBytes / MemoryLayout<UInt64>.size)
        var random = SystemRandomNumberGenerator()
        for i in words.indices { words[i] = random.next() }
        return words.withUnsafeBytes { Data($0) }
    }

    private static func randomAccess(_ url: URL, writing block: Data?) throws {
        let descriptor = open(url.path, block == nil ? O_RDONLY : O_WRONLY)
        guard descriptor >= 0 else { throw QualityIssue.fileError }
        defer { close(descriptor) }
        guard fcntl(descriptor, F_NOCACHE, 1) == 0 else { throw QualityIssue.fileError }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let blockCount = storageBytes / randomBlockBytes
        for index in 0..<randomOperations {
            try Task.checkCancellation()
            // A fixed permutation of 4 KiB-aligned positions, without repeating a position.
            let slot = (index * 4051 + 97) % blockCount
            try handle.seek(toOffset: UInt64(slot * randomBlockBytes))
            if let block { try handle.write(contentsOf: block) }
            else if try handle.read(upToCount: randomBlockBytes)?.count != randomBlockBytes { throw QualityIssue.fileError }
        }
        if block != nil { try handle.synchronize() }
    }

    private static func write(_ block: Data, to url: URL, createdFile: inout Bool) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw QualityIssue.fileError }
        createdFile = true
        defer { close(descriptor) }
        guard fcntl(descriptor, F_NOCACHE, 1) == 0 else { throw QualityIssue.fileError }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        for _ in 0..<(storageBytes / block.count) {
            try Task.checkCancellation()
            try handle.write(contentsOf: block)
        }
        try Task.checkCancellation()
        try handle.synchronize()
    }

    private static func read(from url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw QualityIssue.fileError }
        defer { close(descriptor) }
        guard fcntl(descriptor, F_NOCACHE, 1) == 0 else { throw QualityIssue.fileError }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var remaining = storageBytes
        while remaining > 0 {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: min(blockBytes, remaining)), !data.isEmpty else {
                throw QualityIssue.fileError
            }
            remaining -= data.count
        }
    }
}
