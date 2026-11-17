import CryptoKit
import Darwin
import Foundation

public actor HardwareQualityService {
    public static let cpuBytes = 128 * 1_048_576
    public static let storageBytes = 64 * 1_048_576
    private static let blockBytes = 1_048_576
    private static let shared = HardwareQualityService()
    private var running = false

    private init() {}

    /// Measure single-thread SHA-256 and sequential file I/O on an iPhone. Cancel the calling task to stop.
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
        if !Task.isCancelled {
            let cpuBlock = Data(repeating: 0xA5, count: blockBytes)
            report.currentStep = .cpu
            report.cpu = .running
            await onProgress(report)
            report.cpu = measure(bytes: cpuBytes) { try hash(cpuBlock) }
        }
        if !Task.isCancelled {
            var words = [UInt64](repeating: 0, count: blockBytes / MemoryLayout<UInt64>.size)
            var random = SystemRandomNumberGenerator()
            for i in words.indices { words[i] = random.next() }
            let storageBlock = words.withUnsafeBytes { Data($0) }
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
        return HardwareQualityReport(
            id: UUID(), startedAt: .now, deviceModel: model,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
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
            let elapsed = start.duration(to: .now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            guard seconds > 0 else { return .unavailable(.insufficientSamples) }
            return .measured(.init(bytes: bytes, seconds: seconds, thermalState: thermal))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .unavailable(.fileError)
        }
    }

    private static func hash(_ block: Data) throws {
        var digest = SHA256()
        for _ in 0..<(cpuBytes / block.count) {
            try Task.checkCancellation()
            digest.update(data: block)
        }
        _ = digest.finalize()
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
