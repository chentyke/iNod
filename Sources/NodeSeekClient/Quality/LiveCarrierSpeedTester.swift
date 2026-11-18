import Foundation
import NodeSeekCore

/// Runs `QualityCarrierSpeedService` and turns its reports into the snapshots the carrier speed screen draws.
public struct LiveCarrierSpeedTester: CarrierSpeedTesting {
    private let service: QualityCarrierSpeedService
    private let configured: [QualityCarrierSpeedNode]

    public init() {
        self.init(service: QualityCarrierSpeedService(), nodes: [.taiyuanUnicom])
    }

    init(service: QualityCarrierSpeedService, nodes: [QualityCarrierSpeedNode]) {
        self.service = service
        self.configured = nodes
    }

    public var nodes: [CarrierSpeedNode] { configured.map(Self.node) }

    public func run(_ node: CarrierSpeedNode) -> AsyncStream<CarrierSpeedReport> {
        let (stream, continuation) = AsyncStream.makeStream(of: CarrierSpeedReport.self)
        let initial = CarrierSpeedReport(node: node, startedAt: .now, network: .init(kind: .other))
        continuation.yield(initial)
        guard let target = configured.first(where: { Self.node($0).id == node.id }) else {
            var failed = initial
            failed.speed = .failed(.init(.other, detail: "没有找到这个测速节点"))
            failed.finishedAt = .now
            continuation.yield(failed)
            continuation.finish()
            return stream
        }
        let service = service
        let task = Task {
            do {
                let result = try await service.run(at: target) { raw in
                    continuation.yield(Self.apply(raw, to: initial))
                }
                continuation.yield(Self.apply(result.report, to: initial))
            } catch {
                guard !Task.isCancelled else { return continuation.finish() }
                var failed = initial
                let problem = error as? QualityIssue ?? .invalidResponse
                failed.speed = .failed(LiveNetworkQualityTester.issue(problem, detail: "测速节点配置无效"))
                failed.finishedAt = .now
                continuation.yield(failed)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    static func node(_ node: QualityCarrierSpeedNode) -> CarrierSpeedNode {
        CarrierSpeedNode(carrier: node.carrier, city: node.city, provider: provider(node.format),
                         host: node.downloadURL.host(), maximumBytes: Int64(QualityCarrierSpeedService.maximumTransferBytesPerNode))
    }

    private static func provider(_ format: QualityCarrierSpeedNode.Format?) -> String {
        format == .speedTestCN ? "SpeedTest.cn" : "LibreSpeed"
    }
}

extension LiveCarrierSpeedTester {
    private static let steps: [NetworkQualityReport.Step] = [.latency, .download, .upload]

    /// Mirrors how the main check maps its speed steps, with the carrier node as the server.
    static func apply(_ raw: NetworkQualityReport, to initial: CarrierSpeedReport) -> CarrierSpeedReport {
        var report = initial
        if let kind = kind(raw.network) { report.network = .init(kind: kind) }
        let finished = raw.finishedAt != nil
        // A run stopped by a network change leaves later steps pending; they did not run for the same reason.
        let stopped: QualityIssue? = if case .interrupted(let issue) = raw.state { issue } else { nil }
        let measured = speed(raw, node: initial.node, stopped: stopped)
        if finished || raw.completedStepCount >= steps.count {
            report.partialSpeed = nil
            report.finishedAt = raw.finishedAt ?? .now
            if let measured {
                report.speed = .measured(measured)
            } else if raw.state == .cancelled {
                report.speed = .cancelled
            } else {
                let problem = stopped ?? raw.latency.issue ?? raw.download.issue ?? raw.upload.issue ?? .invalidResponse
                report.speed = .failed(LiveNetworkQualityTester.issue(problem))
            }
        } else {
            report.partialSpeed = measured
            let active = raw.currentStep ?? steps[min(raw.completedStepCount, steps.count - 1)]
            let stage: QualityStage = switch active { case .download: .download; case .upload: .upload; default: .latency }
            let fraction = (Double(raw.completedStepCount) + (raw.stepFraction ?? 0)) / Double(steps.count)
            report.speed = .running(.init(fraction: fraction, stage: stage, currentMbps: raw.currentMbps))
        }
        return report
    }

    private static func speed(_ raw: NetworkQualityReport, node: CarrierSpeedNode, stopped: QualityIssue?) -> SpeedMeasurement? {
        let download = raw.download.value
        let upload = raw.upload.value
        let latency = raw.latency.value
        guard download != nil || upload != nil || latency != nil else { return nil }
        let samples = (download?.samples ?? []) + (upload?.samples ?? [])
        let server = SpeedServer(provider: node.provider, location: "\(node.city)\(node.carrier.title)", host: node.host)
        let transferred = samples.filter { $0.seconds != nil }.reduce(Int64(0)) { $0 + Int64($1.bytes) }
        func problem(_ check: QualityCheck<some Codable & Equatable & Sendable>) -> QualityIssue? {
            if let issue = check.issue { return issue }
            if case .pending = check, let stopped { return stopped }
            return nil
        }
        let problems: [(QualityIssue?, String)] = [(problem(raw.download), "下载"), (problem(raw.upload), "上传"), (problem(raw.latency), "延迟")]
        var result = SpeedMeasurement(
            server: server, downloadMbps: download?.megabitsPerSecond, uploadMbps: upload?.megabitsPerSecond,
            latencyMs: latency?.milliseconds, jitterMs: latency?.jitterMilliseconds,
            latencySamples: latency?.samples.filter { $0.milliseconds != nil }.count ?? 0,
            bytesTransferred: transferred,
            issues: problems.compactMap { problem, name in problem.map { LiveNetworkQualityTester.issue($0, detail: name + "未测得") } }
        )
        result.downloadIsEstimate = download?.isEstimate
        result.uploadIsEstimate = upload?.isEstimate
        return result
    }

    private static func kind(_ network: NetworkQualityReport.Network) -> NetworkKind? {
        switch network {
        case .wifi: .wifi
        case .cellular: .cellular
        case .ethernet: .wired
        case .offline: .offline
        case .other: .other
        case .unknown: nil
        }
    }
}
