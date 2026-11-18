import Foundation
import NodeSeekCore

/// Drives the same report format used by the screen and its sample data.
public struct LiveNetworkQualityTester: NetworkQualityTesting {
    typealias Report = NodeSeekCore.NetworkQualityReport
    private let basics: NetworkQualityService
    private let paths: @Sendable () -> AsyncStream<QualityNetworkPath>

    public init() {
        self.init(basics: NetworkQualityService(), paths: QualityNetworkPath.updates)
    }

    init(basics: NetworkQualityService, paths: @escaping @Sendable () -> AsyncStream<QualityNetworkPath>) {
        self.basics = basics
        self.paths = paths
    }

    public var estimatedUsage: ClosedRange<Int64> {
        let speedBytes = Int64(NetworkQualityService.maximumTransferBytes)
        return speedBytes...(speedBytes + 8_000_000)
    }

    public var supportedSteps: [NetworkQualityStep] { NetworkQualityStep.allCases }

    public func run(_ steps: [NetworkQualityStep], continuing previous: NodeSeekCore.NetworkQualityReport?) -> AsyncStream<NodeSeekCore.NetworkQualityReport> {
        let requested = Set(steps)
        let empty = Report(startedAt: .now, network: .init(kind: .other), speed: .notIncluded, ipv4: .notIncluded, ipv6: .notIncluded)
        var report = (previous ?? empty).resetting(requested)
        if requested.contains(.speed), Self.basicSteps([.speed], previous: previous) != Self.speedSteps {
            report.partialSpeed = previous?.speed.value
        }
        let initial = report
        let (stream, continuation) = AsyncStream.makeStream(of: Report.self)
        continuation.yield(initial)
        let task = Task {
            let final = await run(requested, from: initial, previous: previous) { continuation.yield($0) }
            continuation.yield(final)
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private enum Event: Sendable {
        case measured(Report)
        case interrupted(QualityIssue)
        case monitorEnded
    }

    private func run(
        _ requested: Set<NetworkQualityStep>, from initial: Report, previous: Report?, publish: @escaping @Sendable (Report) -> Void
    ) async -> Report {
        let updates = paths()
        var iterator = updates.makeAsyncIterator()
        var start = initial
        guard let path = await iterator.next(), !Task.isCancelled else {
            return Task.isCancelled ? initial.cancellingUnfinished() : Self.finish(start, interruption: .offline)
        }
        if previous == nil { start.network = path.context }
        guard path.network != .offline else { return Self.finish(start, interruption: .offline) }
        if let previous, previous.includedSteps.contains(where: { previous.status(of: $0) == .measured }),
           previous.network.kind != path.context.kind {
            return Self.finish(start, interruption: .networkChanged)
        }
        start.network = path.context
        let activeReport = start
        publish(activeReport)
        return await withTaskGroup(of: Event.self) { group in
            group.addTask { .measured(await measure(requested, from: activeReport, previous: previous, publish: publish)) }
            group.addTask {
                if let issue = await QualityNetworkPath.interruption(in: updates, after: path) {
                    return .interrupted(issue)
                }
                return .monitorEnded
            }
            var latest = activeReport
            var interruption: QualityIssue?
            for await event in group {
                switch event {
                case .measured(let report): latest = report; group.cancelAll()
                case .interrupted(let issue): interruption = issue; group.cancelAll()
                case .monitorEnded: break
                }
            }
            if Task.isCancelled { return latest.cancellingUnfinished() }
            return Self.finish(latest, interruption: interruption)
        }
    }

    private func measure(
        _ requested: Set<NetworkQualityStep>, from initial: Report, previous: Report?, publish: @escaping @Sendable (Report) -> Void
    ) async -> Report {
        var report = initial
        let steps = Self.basicSteps(requested, previous: previous)
        if !steps.isEmpty {
            let before = report
            let raw = await basics.run(steps: steps) {
                publish(Self.apply($0, to: before, selected: steps, previousSpeed: previous?.speed.value))
            }
            report = Self.apply(raw, to: before, selected: steps, previousSpeed: previous?.speed.value)
            if case .interrupted(let issue) = raw.state { return Self.finish(report, interruption: issue) }
        }
        let session = QualityHTTP.makeSession()
        defer { session.invalidateAndCancel() }
        let send: QualityHTTP.Request = { try await QualityHTTP.request(using: session, request: $0, upload: $1) }
        for step in NetworkQualityStep.advanced where requested.contains(step) {
            guard !Task.isCancelled else { break }
            report.setRunning(step, .init(stage: step == .routes ? .tracing : .querying))
            publish(report)
            let updated = await Self.measureAdvanced(step, in: report, previous: previous, send: send)
            guard !Task.isCancelled else { break }
            report = updated
            publish(report)
        }
        return report
    }

    private static func finish(_ report: Report, interruption: QualityIssue?) -> Report {
        var report = report
        if let interruption {
            for step in report.includedSteps where !report.status(of: step).isFinished {
                report.setFailed(step, issue(interruption))
            }
        }
        report.finishedAt = .now
        return report
    }
}

extension LiveNetworkQualityTester {
    private static let speedSteps: [NetworkQualityReport.Step] = [.latency, .download, .upload]

    static func basicSteps(_ requested: Set<NetworkQualityStep>, previous: Report?) -> [NetworkQualityReport.Step] {
        var result: [NetworkQualityReport.Step] = []
        if requested.contains(.speed) {
            if let speed = previous?.speed.value {
                if speed.latencyMs == nil || speed.jitterMs == nil { result.append(.latency) }
                if speed.downloadMbps == nil { result.append(.download) }
                if speed.uploadMbps == nil { result.append(.upload) }
                if result.isEmpty { result = speedSteps }
            } else { result = speedSteps }
        }
        if requested.contains(.ipv4) { result.append(.ipv4) }
        if requested.contains(.ipv6) { result.append(.ipv6) }
        return result
    }

    private static func apply(
        _ raw: NetworkQualityReport, to initial: Report, selected: [NetworkQualityReport.Step], previousSpeed: SpeedMeasurement?
    ) -> Report {
        var report = initial
        let speedChecks = selected.filter { speedSteps.contains($0) }
        if !speedChecks.isEmpty {
            let previous = speedChecks == speedSteps ? nil : previousSpeed
            let measured = speed(raw, previous: previous)
            report.partialSpeed = measured
            if raw.completedStepCount >= speedChecks.count || raw.finishedAt != nil {
                if let measured { report.speed = .measured(measured); report.partialSpeed = nil }
                else if let problem = raw.download.issue ?? raw.upload.issue ?? raw.latency.issue { report.speed = .failed(issue(problem)) }
            } else if raw.completedStepCount > 0 || raw.currentStep != nil {
                let active = raw.currentStep ?? speedChecks[min(raw.completedStepCount, speedChecks.count - 1)]
                let stage: QualityStage = switch active { case .download: .download; case .upload: .upload; default: .latency }
                let fraction = (Double(raw.completedStepCount) + (raw.stepFraction ?? 0)) / Double(speedChecks.count)
                report.speed = .running(.init(fraction: fraction, stage: stage, currentMbps: raw.currentMbps))
            }
        }
        if selected.contains(.ipv4) { report.ipv4 = address(raw.ipv4, family: .v4) }
        if selected.contains(.ipv6) { report.ipv6 = address(raw.ipv6, family: .v6) }
        return report
    }

    private static func speed(_ raw: NetworkQualityReport, previous: SpeedMeasurement?) -> SpeedMeasurement? {
        let download = raw.download.value
        let upload = raw.upload.value
        let latency = raw.latency.value
        guard download != nil || upload != nil || latency != nil || previous != nil else { return nil }
        let transferSamples = (download?.samples ?? []) + (upload?.samples ?? [])
        var nodes = Set(transferSamples.compactMap(\.node) + (latency?.samples.compactMap(\.node) ?? []))
        if let previous, !previous.server.location.isEmpty {
            nodes.formUnion(previous.server.location.components(separatedBy: "、"))
        }
        let server = SpeedServer(provider: "Cloudflare", location: nodes.sorted().joined(separator: "、"), host: "speed.cloudflare.com")
        let transferred = transferSamples.filter { $0.seconds != nil }.reduce(Int64(0)) { $0 + Int64($1.bytes) }
        let problems: [(QualityIssue?, String)] = [(raw.download.issue, "下载"), (raw.upload.issue, "上传"), (raw.latency.issue, "延迟")]
        var result = SpeedMeasurement(
            server: server, downloadMbps: download?.megabitsPerSecond ?? previous?.downloadMbps,
            uploadMbps: upload?.megabitsPerSecond ?? previous?.uploadMbps,
            latencyMs: latency?.milliseconds ?? previous?.latencyMs, jitterMs: latency?.jitterMilliseconds ?? previous?.jitterMs,
            latencySamples: latency?.samples.filter { $0.milliseconds != nil }.count ?? previous?.latencySamples ?? 0,
            bytesTransferred: transferred + (previous?.bytesTransferred ?? 0),
            issues: problems.compactMap { problem, name in
                problem.map { issue($0, detail: name + "未测得") }
            }
        )
        result.downloadIsEstimate = download?.isEstimate ?? previous?.downloadIsEstimate
        result.uploadIsEstimate = upload?.isEstimate ?? previous?.uploadIsEstimate
        return result
    }

    private static func address(_ result: QualityCheck<QualityPublicIP>, family: IPFamily) -> QualityResult<IPEgress> {
        switch result {
        case .pending: return .pending
        case .running: return .running(.init(stage: .lookingUpOwner))
        case .cancelled: return .cancelled
        case .unavailable(let problem): return .failed(issue(problem))
        case .measured(let ip):
            let owner = ip.attribution.value.map { value in
                IPOwner(country: value.countryCode.flatMap { Locale(identifier: "zh_CN").localizedString(forRegionCode: $0) },
                        countryCode: value.countryCode, region: value.region, city: value.city,
                        asn: value.asn.flatMap { Int($0.dropFirst(2)) }, organization: value.networkName,
                        source: ip.attributionSource?.endpoint.host() ?? "IPinfo")
            }
            return .measured(IPEgress(family: family, address: ip.address, echoSource: ip.source.endpoint.host() ?? ip.source.provider,
                                      owner: owner, ownerIssue: ip.attribution.issue.map { issue($0) },
                                      queriedAt: ip.attributionSource?.checkedAt ?? ip.source.checkedAt))
        }
    }

    private static func measureAdvanced(
        _ step: NetworkQualityStep, in report: Report, previous: Report?, send: @escaping QualityHTTP.Request
    ) async -> Report {
        var report = report
        switch step {
        case .routes:
            let past = previous?.routes.value ?? []
            let failures = Set(past.filter { $0.issue != nil }.map(\.target))
            let values = await QualityRoutes.measure(hosts: failures.isEmpty ? nil : failures, send: send)
            let observed = values.compactMap(route)
            report.routes = .measured(merge(observed, kept: failures.isEmpty ? [] : past))
        case .nat:
            let attempts = await QualitySTUN.measure()
            let best = attempts.first { $0.result.value != nil } ?? attempts.first { !$0.samples.isEmpty } ?? attempts.last
            if let best {
                let mapping: NATType = switch best.result.value {
                case .endpointIndependent: .endpointIndependent
                case .addressDependent: .addressDependent
                case .addressAndPortDependent: .addressAndPortDependent
                case nil: .undetermined
                }
                let sample = best.samples.first
                report.nat = .measured(.init(type: mapping, server: "\(best.host):\(best.port)",
                                             mappedEndpoint: sample.map { "\($0.publicAddress):\($0.publicPort)" },
                                             issue: best.result.issue.map { issue($0) }))
            } else { report.nat = .failed(.init(.serviceUnavailable)) }
        case .mailPort:
            let test = await AdvancedNetworkQualityService.mailAccess()
            if let value = test.result.value {
                let outcome: PortOutcome = switch value { case .connected: .open; case .refused: .refused; case .timedOut: .timedOut }
                report.mailPort = .measured(.init(target: test.host, port: Int(test.port), outcome: outcome))
            } else { report.mailPort = .failed(issue(test.result.issue ?? .invalidResponse)) }
        case .reputation:
            let addresses: [(QualityIPFamily, String)] = [(.ipv4, report.ipv4.value), (.ipv6, report.ipv6.value)].compactMap { family, ip in
                ip.map { (family, $0.address) }
            }
            guard !addresses.isEmpty else {
                report.reputation = .failed(.init(.other, detail: "需要先测得公网地址"))
                return report
            }
            let past = previous?.reputation.value ?? []
            let failures = Set(past.filter { $0.issue != nil }.map(\.id))
            let results = await QualityReputation.lookup(addresses: addresses, ids: failures.isEmpty ? nil : failures, send: send)
            let records = results.map(reputation)
            report.reputation = .measured(merge(records, kept: failures.isEmpty ? [] : past))
        case .services:
            let past = previous?.services.value ?? []
            let failures = Set(past.filter { $0.issue != nil }.map(\.name))
            let results = await AdvancedNetworkQualityService.websiteAccess(names: failures.isEmpty ? nil : failures, send: send)
            report.services = .measured(merge(results.map(service), kept: failures.isEmpty ? [] : past))
        case .speed, .ipv4, .ipv6: break
        }
        return report
    }

    private static func merge<T: Identifiable>(_ updated: [T], kept: [T]) -> [T] {
        let latest = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        let existingIDs = Set(kept.map(\.id))
        return kept.map { latest[$0.id] ?? $0 } + updated.filter { !existingIDs.contains($0.id) }
    }

    private static func route(_ raw: QualityRouteReport) -> RouteTrace? {
        let carrier: ChinaCarrier
        switch raw.carrier {
        case "中国电信": carrier = .telecom
        case "中国联通": carrier = .unicom
        case "中国移动": carrier = .mobile
        default: return nil
        }
        let hops = raw.hops.map { hop in
            let owner = [hop.network?.asn, hop.network?.networkName].compactMap { $0 }.joined(separator: " ")
            return RouteHop(index: hop.number, address: hop.address, rttMs: hop.milliseconds, owner: owner.isEmpty ? nil : owner)
        }
        return RouteTrace(carrier: carrier, city: raw.city, family: raw.family == .ipv4 ? .v4 : .v6,
                          target: raw.host, sent: raw.sent, received: raw.received, averageLatencyMs: raw.averageLatencyMs,
                          hops: hops, issue: raw.issue.map { issue($0) })
    }

    private static func reputation(_ raw: QualityIPReputation) -> ReputationRecord {
        let verdict: ReputationVerdict
        let label: String?
        switch raw.result.value {
        case .listed(let reference): verdict = .listed; label = reference
        case .notListed: verdict = .notListed; label = nil
        case nil: verdict = .unknown; label = nil
        }
        return ReputationRecord(source: raw.source.provider, family: raw.family == .ipv4 ? .v4 : .v6,
                                verdict: verdict, label: label, queriedAt: raw.source.checkedAt, issue: raw.result.issue.map { issue($0) })
    }

    private static func service(_ raw: QualityServiceAccess) -> ServiceProbe {
        let outcome: ServiceOutcome
        let status: Int?
        switch raw.result.value {
        case .webpageAccessible(let code): outcome = .reachable; status = code
        case .redirected(let code): outcome = .redirected; status = code
        case .legallyRestricted(let code): outcome = .legallyRestricted; status = code
        case nil: outcome = raw.result.issue == .timedOut ? .timedOut : .undetermined; status = nil
        }
        return ServiceProbe(name: raw.source.provider, outcome: outcome, basis: .webPage, endpoint: raw.source.endpoint,
                            issue: raw.result.issue.map { issue($0) }, httpStatus: status)
    }

    static func issue(_ problem: QualityIssue, detail: String? = nil) -> NodeSeekCore.QualityIssue {
        switch problem {
        case .offline: .init(.offline, detail: detail)
        case .networkChanged: .init(.networkChanged, detail: detail)
        case .timedOut: .init(.timedOut, detail: detail)
        case .httpStatus(429): .init(.rateLimited, detail: detail)
        case .httpStatus(let status): .init(.serviceUnavailable, detail: [detail, "HTTP \(status)"].compactMap { $0 }.joined(separator: "，"))
        case .unsupportedDevice: .init(.notSupported)
        case .unsupportedMeasurement: .init(.other, detail: "检测节点没有提供所需的备用地址")
        case .alreadyRunning: .init(.other, detail: "已有一项硬件测试正在运行")
        case .wrongAddressFamily: .init(.other, detail: "服务返回了不同类型的地址")
        case .fileError, .prerequisiteFailed: .init(.other, detail: "未能读写测试文件")
        case .hostUnreachable, .invalidResponse, .transportError, .insufficientSamples, .cancelled:
            .init(.serviceUnavailable, detail: detail)
        }
    }
}
