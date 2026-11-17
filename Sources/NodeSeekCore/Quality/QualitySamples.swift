import Foundation

/// Sample results for building and testing the UI before the detection services land.
/// Addresses come from the documentation ranges (RFC 5737, RFC 3849), so nothing real leaks into screenshots.
public enum QualitySampleScenario: String, Sendable, CaseIterable {
    /// Everything measured, Wi‑Fi, both address families.
    case complete
    /// Cellular, no IPv6, owner lookup and one reputation source failed, a route with silent hops, upload timed out.
    case partialFailure
    /// Every network step fails because the connection dropped.
    case offline
}

public extension NetworkQualityReport {
    static func sample(_ scenario: QualitySampleScenario, at date: Date = Date(timeIntervalSince1970: 1_795_420_800)) -> Self {
        let cloudflare = SpeedServer(provider: "Cloudflare", location: "香港", host: "speed.cloudflare.com")
        let v4Owner = IPOwner(country: "中国", countryCode: "CN", region: "上海", city: "上海", asn: 4812, organization: "中国电信", source: "ipinfo.io")
        let v6Owner = IPOwner(country: "中国", countryCode: "CN", region: "上海", city: "上海", asn: 4812, organization: "中国电信", source: "ipinfo.io")
        switch scenario {
        case .complete:
            return .init(
                startedAt: date, finishedAt: date.addingTimeInterval(74),
                network: .init(kind: .wifi),
                speed: .measured(.init(server: cloudflare, downloadMbps: 486.3, uploadMbps: 52.7, latencyMs: 31.4, jitterMs: 2.1,
                                       latencySamples: 20, bytesTransferred: 412_000_000)),
                ipv4: .measured(.init(family: .v4, address: "203.0.113.24", echoSource: "cloudflare.com/cdn-cgi/trace", owner: v4Owner, queriedAt: date.addingTimeInterval(40))),
                ipv6: .measured(.init(family: .v6, address: "2001:db8:4c2a:1f00:9d3e:21ff:fe4b:7a10", echoSource: "cloudflare.com/cdn-cgi/trace", owner: v6Owner, queriedAt: date.addingTimeInterval(41))),
                routes: .measured(ChinaCarrier.allCases.map { carrier in
                    RouteTrace(carrier: carrier, city: "上海", family: .v4, target: sampleTarget(carrier), sent: 20, received: carrier == .mobile ? 19 : 20,
                               averageLatencyMs: carrier == .telecom ? 4.8 : carrier == .unicom ? 9.6 : 12.3, hops: sampleHops(carrier, silentAt: []))
                }),
                nat: .measured(.init(type: .portRestrictedCone, server: "stun.cloudflare.com", mappedEndpoint: "203.0.113.24:51820")),
                mailPort: .measured(.init(target: "smtp.gmail.com", port: 25, outcome: .timedOut)),
                reputation: .measured([
                    .init(source: "IPinfo", family: .v4, verdict: .clean, label: "家庭宽带", queriedAt: date.addingTimeInterval(60)),
                    .init(source: "Scamalytics", family: .v4, verdict: .low, label: "风险分 4", queriedAt: date.addingTimeInterval(61)),
                    .init(source: "AbuseIPDB", family: .v4, verdict: .clean, label: "0 次举报", queriedAt: date.addingTimeInterval(61)),
                    .init(source: "IPinfo", family: .v6, verdict: .clean, label: "家庭宽带", queriedAt: date.addingTimeInterval(62)),
                ]),
                services: .measured([
                    .init(name: "Netflix", outcome: .regionRestricted, basis: .regionCheck, region: "仅自制剧"),
                    .init(name: "YouTube", outcome: .reachable, basis: .regionCheck, region: "香港"),
                    .init(name: "ChatGPT", outcome: .regionRestricted, basis: .regionCheck),
                    .init(name: "GitHub", outcome: .reachable, basis: .webPage),
                    .init(name: "Telegram", outcome: .timedOut, basis: .webPage),
                ])
            )
        case .partialFailure:
            return .init(
                startedAt: date, finishedAt: date.addingTimeInterval(96),
                network: .init(kind: .cellular, isExpensive: true),
                speed: .measured(.init(server: cloudflare, downloadMbps: 128.9, uploadMbps: nil, latencyMs: 48.2, jitterMs: 11.7,
                                       latencySamples: 20, bytesTransferred: 96_000_000, issues: [.init(.timedOut, detail: "上传 30 秒内未完成")])),
                ipv4: .measured(.init(family: .v4, address: "198.51.100.173", echoSource: "cloudflare.com/cdn-cgi/trace", owner: nil,
                                      ownerIssue: .init(.rateLimited, detail: "ipinfo.io 返回 429"), queriedAt: date.addingTimeInterval(52))),
                ipv6: .unavailable(.init(.noIPv6)),
                routes: .measured([
                    .init(carrier: .telecom, city: "上海", family: .v4, target: sampleTarget(.telecom), sent: 20, received: 17, averageLatencyMs: 38.5,
                          hops: sampleHops(.telecom, silentAt: [3, 4])),
                    .init(carrier: .unicom, city: "上海", family: .v4, target: sampleTarget(.unicom), sent: 20, received: 20, averageLatencyMs: 41.0,
                          hops: sampleHops(.unicom, silentAt: [2])),
                    .init(carrier: .mobile, city: "上海", family: .v4, target: sampleTarget(.mobile), sent: 0, received: 0, averageLatencyMs: nil,
                          hops: [], issue: .init(.timedOut, detail: "测试节点没有回应")),
                ]),
                nat: .measured(.init(type: .symmetric, server: "stun.cloudflare.com", mappedEndpoint: "198.51.100.173:40112")),
                mailPort: .measured(.init(target: "smtp.gmail.com", port: 25, outcome: .refused)),
                reputation: .measured([
                    .init(source: "IPinfo", family: .v4, verdict: .clean, label: "移动网络", queriedAt: date.addingTimeInterval(80)),
                    .init(source: "Scamalytics", family: .v4, verdict: .high, label: "风险分 78", queriedAt: date.addingTimeInterval(81)),
                    .init(source: "AbuseIPDB", family: .v4, verdict: .unknown, queriedAt: date.addingTimeInterval(81), issue: .init(.serviceUnavailable)),
                ]),
                services: .failed(.init(.networkChanged, detail: "测试中从 Wi‑Fi 切换到了蜂窝网络"))
            )
        case .offline:
            let dropped = QualityIssue(.offline)
            return .init(startedAt: date, finishedAt: date.addingTimeInterval(9), network: .init(kind: .offline),
                         speed: .failed(dropped), ipv4: .failed(dropped), ipv6: .failed(dropped), routes: .failed(dropped),
                         nat: .failed(dropped), mailPort: .failed(dropped), reputation: .failed(dropped), services: .failed(dropped))
        }
    }

    private static func sampleTarget(_ carrier: ChinaCarrier) -> String {
        switch carrier { case .telecom: "203.0.113.1"; case .unicom: "198.51.100.1"; case .mobile: "192.0.2.1" }
    }

    private static func sampleHops(_ carrier: ChinaCarrier, silentAt silent: Set<Int>) -> [RouteHop] {
        let backbone = switch carrier { case .telecom: "AS4134 中国电信"; case .unicom: "AS4837 中国联通"; case .mobile: "AS9808 中国移动" }
        return (1...7).map { index in
            if silent.contains(index) { return RouteHop(index: index, address: nil) }
            let owner = index == 1 ? "局域网" : index < 4 ? "AS4812 中国电信上海" : backbone
            return RouteHop(index: index, address: index == 1 ? "192.168.1.1" : "192.0.2.\(10 + index * 7)", rttMs: Double(index) * 1.7 + 0.8, owner: owner)
        }
    }
}

public extension DeviceBenchmarkReport {
    static func sample(at date: Date = Date(timeIntervalSince1970: 1_795_420_800), cpuScale: Double = 1, thermal: ThermalLevel = .fair) -> Self {
        .init(startedAt: date, finishedAt: date.addingTimeInterval(58),
              device: .init(model: "iPhone 17 Pro", systemVersion: "26.1", processorCount: 6), method: "iNod Bench 1",
              thermalAtStart: .nominal, thermalAtEnd: thermal,
              cpuSingle: .measured(.init(score: Int(3_412 * cpuScale), threads: 1, duration: 10)),
              cpuMulti: .measured(.init(score: Int(8_976 * cpuScale), threads: 6, duration: 10)),
              storageSequential: .measured(.init(readMBps: 1_842, writeMBps: 1_206, blockSize: 1 << 20, fileBytes: 256 << 20)),
              storageRandom: .measured(.init(readMBps: 214.5, writeMBps: 96.8, readIOPS: 52_400, writeIOPS: 23_600, blockSize: 4_096, fileBytes: 64 << 20)))
    }
}

/// Plays a sample report back step by step, with the live progress a real run would show.
public struct SampleNetworkQualityTester: NetworkQualityTesting {
    public var scenario: QualitySampleScenario
    /// Seconds per step; UI tests shorten it.
    public var pace: Double
    public init(scenario: QualitySampleScenario = .complete, pace: Double = 1) { self.scenario = scenario; self.pace = pace }

    public var estimatedUsage: ClosedRange<Int64> { 50_000_000...450_000_000 }
    public var supportedSteps: [NetworkQualityStep] { NetworkQualityStep.allCases }

    public func run(_ steps: [NetworkQualityStep], continuing previous: NetworkQualityReport?) -> AsyncStream<NetworkQualityReport> {
        let final = NetworkQualityReport.sample(scenario, at: .now)
        let pace = pace
        return AsyncStream { continuation in
            let task = Task {
                var report = previous?.resetting(Set(steps)) ?? NetworkQualityReport(
                    startedAt: .now, network: final.network,
                    speed: .pending, ipv4: .pending, ipv6: .pending, routes: .pending,
                    nat: .pending, mailPort: .pending, reputation: .pending, services: .pending)
                for step in NetworkQualityStep.allCases where !steps.contains(step) && report.status(of: step) == .pending {
                    report.set(step, from: NetworkQualityReport(startedAt: .now, network: final.network, speed: .notIncluded, ipv4: .notIncluded, ipv6: .notIncluded))
                }
                continuation.yield(report)
                func wait(_ seconds: Double) async throws { try await Task.sleep(for: .milliseconds(Int(seconds * pace * 1000))) }
                do {
                    for step in steps {
                        if step == .speed {
                            report.speed = .running(.init(stage: .findingServer)); continuation.yield(report); try await wait(0.6)
                            for i in 1...5 { report.speed = .running(.init(fraction: Double(i) / 20, stage: .latency)); continuation.yield(report); try await wait(0.12) }
                            let target = final.speed.value?.downloadMbps ?? 0, upTarget = final.speed.value?.uploadMbps ?? 0
                            for i in 1...14 {
                                let wobble = 0.88 + 0.12 * sin(Double(i))
                                report.speed = .running(.init(fraction: 0.25 + Double(i) / 14 * 0.4, stage: .download, currentMbps: target * min(1, Double(i) / 5) * wobble))
                                continuation.yield(report); try await wait(0.18)
                            }
                            for i in 1...10 {
                                report.speed = .running(.init(fraction: 0.65 + Double(i) / 10 * 0.35, stage: .upload, currentMbps: max(upTarget, 4) * min(1, Double(i) / 4)))
                                continuation.yield(report); try await wait(0.18)
                            }
                        } else {
                            let stage: QualityStage = switch step { case .ipv4, .ipv6: .lookingUpOwner; case .routes: .tracing; default: .querying }
                            for i in 0..<4 { report.setRunning(step, .init(fraction: Double(i) / 4, stage: stage)); continuation.yield(report); try await wait(0.22) }
                        }
                        report.set(step, from: final)
                        continuation.yield(report)
                    }
                    report.finishedAt = .now
                    continuation.yield(report)
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public struct SampleDeviceBenchmark: DeviceBenchmarking {
    public var pace: Double
    public init(pace: Double = 1) { self.pace = pace }
    public var scratchBytes: Int64 { 320_000_000 }

    public func run() -> AsyncStream<DeviceBenchmarkReport> {
        let final = DeviceBenchmarkReport.sample(at: .now, cpuScale: Double.random(in: 0.97...1.02))
        let pace = pace
        return AsyncStream { continuation in
            let task = Task {
                var report = DeviceBenchmarkReport(startedAt: .now, device: final.device, method: final.method, thermalAtStart: final.thermalAtStart)
                continuation.yield(report)
                do {
                    for step in DeviceBenchmarkStep.allCases {
                        for i in 0..<10 {
                            let progress = QualityProgress(fraction: Double(i) / 10)
                            switch step {
                            case .cpuSingle: report.cpuSingle = .running(progress)
                            case .cpuMulti: report.cpuMulti = .running(progress)
                            case .storageSequential: report.storageSequential = .running(progress)
                            case .storageRandom: report.storageRandom = .running(progress)
                            }
                            continuation.yield(report)
                            try await Task.sleep(for: .milliseconds(Int(180 * pace)))
                        }
                        switch step {
                        case .cpuSingle: report.cpuSingle = final.cpuSingle
                        case .cpuMulti: report.cpuMulti = final.cpuMulti
                        case .storageSequential: report.storageSequential = final.storageSequential
                        case .storageRandom: report.storageRandom = final.storageRandom
                        }
                        continuation.yield(report)
                    }
                    report.thermalAtEnd = final.thermalAtEnd; report.finishedAt = .now
                    continuation.yield(report)
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension NetworkQualityReport {
    /// Copies one step's result from `other`.
    mutating func set(_ step: NetworkQualityStep, from other: NetworkQualityReport) {
        switch step {
        case .speed: speed = other.speed
        case .ipv4: ipv4 = other.ipv4
        case .ipv6: ipv6 = other.ipv6
        case .routes: routes = other.routes
        case .nat: nat = other.nat
        case .mailPort: mailPort = other.mailPort
        case .reputation: reputation = other.reputation
        case .services: services = other.services
        }
    }

    mutating func setRunning(_ step: NetworkQualityStep, _ progress: QualityProgress) {
        switch step {
        case .speed: speed = .running(progress)
        case .ipv4: ipv4 = .running(progress)
        case .ipv6: ipv6 = .running(progress)
        case .routes: routes = .running(progress)
        case .nat: nat = .running(progress)
        case .mailPort: mailPort = .running(progress)
        case .reputation: reputation = .running(progress)
        case .services: services = .running(progress)
        }
    }
}
