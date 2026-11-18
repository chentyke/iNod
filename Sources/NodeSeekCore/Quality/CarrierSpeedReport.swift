import Foundation

/// A carrier's speed test node the reader can pick, separate from the main check's Cloudflare test.
public struct CarrierSpeedNode: Sendable, Equatable, Codable, Identifiable {
    public var carrier: ChinaCarrier
    public var city: String
    /// Who runs the node, e.g. "SpeedTest.cn".
    public var provider: String
    public var host: String?
    /// The most test data one run sends and receives, before protocol overhead.
    public var maximumBytes: Int64
    public var id: String { "\(carrier.rawValue)-\(city)" }

    public init(carrier: ChinaCarrier, city: String, provider: String, host: String? = nil, maximumBytes: Int64) {
        self.carrier = carrier; self.city = city; self.provider = provider; self.host = host; self.maximumBytes = maximumBytes
    }
}

/// One speed test against a carrier node. The service sends a fresh snapshot after every change.
public struct CarrierSpeedReport: Sendable, Equatable, Codable {
    public var node: CarrierSpeedNode
    public var startedAt: Date
    public var finishedAt: Date?
    public var network: NetworkContext
    public var speed: QualityResult<SpeedMeasurement>
    /// What has been measured so far while `speed` is running, kept if the reader cancels.
    public var partialSpeed: SpeedMeasurement?

    public init(node: CarrierSpeedNode, startedAt: Date, finishedAt: Date? = nil, network: NetworkContext,
                speed: QualityResult<SpeedMeasurement> = .pending, partialSpeed: SpeedMeasurement? = nil) {
        self.node = node; self.startedAt = startedAt; self.finishedAt = finishedAt; self.network = network
        self.speed = speed; self.partialSpeed = partialSpeed
    }

    public var isFinished: Bool { speed.status.isFinished }

    /// What the report keeps after the reader cancels: directions already measured, the rest marked as cancelled.
    public func cancellingUnfinished(at date: Date = .now) -> Self {
        var copy = self
        if !speed.status.isFinished, var measured = partialSpeed {
            measured.issues.append(Self.cancelledIssue)
            copy.speed = .measured(measured)
        } else {
            copy.speed = speed.cancellingUnfinished
        }
        copy.partialSpeed = nil
        copy.finishedAt = copy.finishedAt ?? date
        return copy
    }

    /// Attached to a measurement whose remaining directions were cancelled.
    public static let cancelledIssue = QualityIssue(.other, detail: "已取消")
}

/// The carrier speed test, as the UI calls it. Same contract as `NetworkQualityTesting`: `run` yields snapshots and
/// finishes when the run ends; the UI stops a run by cancelling the task that iterates the stream.
public protocol CarrierSpeedTesting: Sendable {
    /// Nodes that have been checked to work. Carriers without a verified node are left out.
    var nodes: [CarrierSpeedNode] { get }
    func run(_ node: CarrierSpeedNode) -> AsyncStream<CarrierSpeedReport>
}

// MARK: - Samples

public extension CarrierSpeedNode {
    /// Matches the public Taiyuan Unicom node without naming its address.
    static let sample = Self(carrier: .unicom, city: "太原", provider: "SpeedTest.cn", maximumBytes: 18 * 1_048_576)
}

public extension CarrierSpeedReport {
    static func sample(_ scenario: QualitySampleScenario, node: CarrierSpeedNode = .sample,
                       at date: Date = Date(timeIntervalSince1970: 1_795_420_800)) -> Self {
        let server = SpeedServer(provider: node.provider, location: "\(node.city)\(node.carrier.title)", host: node.host)
        switch scenario {
        case .complete:
            return .init(node: node, startedAt: date, finishedAt: date.addingTimeInterval(21), network: .init(kind: .wifi),
                         speed: .measured(.init(server: server, downloadMbps: 312.4, uploadMbps: 41.8, latencyMs: 38.6, jitterMs: 3.2,
                                                latencySamples: 5, bytesTransferred: 18 * 1_048_576)))
        case .partialFailure:
            return .init(node: node, startedAt: date, finishedAt: date.addingTimeInterval(34), network: .init(kind: .cellular, isExpensive: true),
                         speed: .measured(.init(server: server, downloadMbps: 86.5, uploadMbps: nil, latencyMs: 52.1, jitterMs: 9.4,
                                                latencySamples: 5, bytesTransferred: 10 * 1_048_576,
                                                issues: [.init(.timedOut, detail: "25 秒内未完成")])))
        case .offline:
            return .init(node: node, startedAt: date, finishedAt: date.addingTimeInterval(2), network: .init(kind: .offline),
                         speed: .failed(.init(.offline)))
        }
    }
}

/// Plays a sample carrier test back with the live progress a real run would show.
public struct SampleCarrierSpeedTester: CarrierSpeedTesting {
    public var scenario: QualitySampleScenario
    /// Seconds per step; UI tests shorten it.
    public var pace: Double
    public init(scenario: QualitySampleScenario = .complete, pace: Double = 1) { self.scenario = scenario; self.pace = pace }

    public var nodes: [CarrierSpeedNode] { [.sample] }

    public func run(_ node: CarrierSpeedNode) -> AsyncStream<CarrierSpeedReport> {
        let final = CarrierSpeedReport.sample(scenario, node: node, at: .now)
        let pace = pace
        return AsyncStream { continuation in
            let task = Task {
                var report = CarrierSpeedReport(node: node, startedAt: .now, network: final.network)
                continuation.yield(report)
                func wait(_ seconds: Double) async throws { try await Task.sleep(for: .milliseconds(Int(seconds * pace * 1000))) }
                do {
                    guard let measured = final.speed.value else {
                        report.speed = .running(.init(stage: .latency)); continuation.yield(report); try await wait(0.6)
                        continuation.yield(final); continuation.finish(); return
                    }
                    for i in 1...5 { report.speed = .running(.init(fraction: Double(i) / 15, stage: .latency)); continuation.yield(report); try await wait(0.12) }
                    var partial = measured
                    partial.downloadMbps = nil; partial.uploadMbps = nil; partial.issues = []
                    report.partialSpeed = partial
                    let download = measured.downloadMbps ?? 0
                    for i in 1...14 {
                        let wobble = 0.88 + 0.12 * sin(Double(i))
                        report.speed = .running(.init(fraction: 1.0 / 3 + Double(i) / 14 / 3, stage: .download, currentMbps: download * min(1, Double(i) / 5) * wobble))
                        continuation.yield(report); try await wait(0.18)
                    }
                    report.partialSpeed?.downloadMbps = measured.downloadMbps
                    let upload = max(measured.uploadMbps ?? 2, 2)
                    for i in 1...10 {
                        report.speed = .running(.init(fraction: 2.0 / 3 + Double(i) / 10 / 3, stage: .upload, currentMbps: upload * min(1, Double(i) / 4)))
                        continuation.yield(report); try await wait(0.18)
                    }
                    continuation.yield(final)
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
