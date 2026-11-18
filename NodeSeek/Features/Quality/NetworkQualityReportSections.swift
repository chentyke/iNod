import NodeSeekCore
import SwiftUI

/// The report body. Before a run each row shows a dash; during a run each row shows its step's state and fills in
/// with its result in place.
struct NetworkQualityReportSections: View {
    let report: NetworkQualityReport?
    let steps: [NetworkQualityStep]
    /// nil while a run is under way.
    let retry: ((NetworkQualityStep) -> Void)?

    private func status(_ step: NetworkQualityStep) -> QualityStatus { report?.status(of: step) ?? .pending }
    private var retryable: [NetworkQualityStep] { report?.retryableSteps ?? [] }

    var body: some View {
        Group {
            if steps.contains(.speed) { speedSection }
            if steps.contains(.ipv4) || steps.contains(.ipv6) { addressSection }
            if steps.contains(.ipDetails) { ipDetailsSection }
            if steps.contains(.routes) { routeSection }
            if steps.contains(.nat) || steps.contains(.mailPort) { connectionSection }
            if steps.contains(.reputation) { reputationSection }
            if steps.contains(.services) { serviceSection }
            if let report, report.finishedAt != nil { methodSection(report) }
        }
        .environment(\.qualityIdle, report == nil)
    }

    // MARK: Speed

    private var speedSection: some View {
        let speed = report?.speed.value, state = status(.speed)
        return Section("速度") {
            if speed == nil {
                // One line until the result arrives, rather than four rows all saying the same thing.
                QualityRow("延迟、抖动和测试节点", status: state, value: "")
            }
            // The header shows both directions; a direction that did not finish says why here.
            if let speed {
                let issue = speed.issues.first ?? QualityIssue(.other)
                if speed.downloadMbps == nil { QualityRow("下载", status: .failed(issue), value: "") }
                if speed.uploadMbps == nil { QualityRow("上传", subtitle: issue.detail, status: .failed(issue), value: "") }
                let missing = QualityStatus.unavailable(.init(.other))
                QualityRow("延迟", subtitle: "\(speed.latencySamples) 次往返的中位数", status: speed.latencyMs == nil ? missing : .measured,
                           value: speed.latencyMs.map { "\(QualityFormat.ms($0)) ms" } ?? "")
                QualityRow("抖动", status: speed.jitterMs == nil ? missing : .measured, value: speed.jitterMs.map { "\(QualityFormat.ms($0)) ms" } ?? "")
                QualityRow("测试节点", status: .measured, value: "\(speed.server.provider) \(speed.server.location)")
                QualityRow("测速数据量", status: .measured, value: QualityFormat.bytes(speed.bytesTransferred))
            }
        }
        .retryMenu(.speed, retryable: retryable.contains(.speed), retry: retry)
    }

    // MARK: Addresses

    private var addressSection: some View {
        Section("公网地址") {
            ForEach([NetworkQualityStep.ipv4, .ipv6].filter(steps.contains)) { step in
                let result = step == .ipv4 ? report?.ipv4 : report?.ipv6
                Group {
                    if let egress = result?.value { EgressRow(egress: egress) }
                    else { QualityRow(step == .ipv4 ? "IPv4" : "IPv6", status: status(step), value: "") }
                }
                .retryMenu(step, retryable: retryable.contains(step), retry: retry)
            }
        }
    }

    // MARK: IP type and routing

    private var ipDetailsSection: some View {
        let profiles = report?.ipDetails.value
        return Section {
            if let profiles {
                ForEach(profiles) { profile in
                    IPUsageRow(profile: profile)
                    BGPRouteRow(profile: profile)
                }
            } else {
                QualityRow("类型、BGP 地址段和发布网络", status: status(.ipDetails), value: "")
            }
        } header: { Text("IP 类型与路由") } footer: {
            if let profiles, !profiles.isEmpty { Text(ipDetailsNote(profiles)) }
        }
        .retryMenu(.ipDetails, retryable: retryable.contains(.ipDetails), retry: retry)
    }

    private func ipDetailsNote(_ profiles: [IPProfile]) -> String {
        var note = "类型和分值由 IPQuery 判定，分值为其自定的 0–100 分，不代表滥用概率。地址段和发布网络来自 RIPE RIS 观察到的 BGP 公告"
        let times = profiles.flatMap { [$0.route.queriedAt, $0.usage.queriedAt] }
        if let time = times.max() { note += "。查询于 \(time.formatted(date: .omitted, time: .shortened))" }
        return note + "。"
    }

    // MARK: Routes

    private var routeSection: some View {
        Section {
            if let traces = report?.routes.value {
                ForEach(traces) { trace in
                    if !trace.hops.isEmpty {
                        NavigationLink { RouteTraceView(trace: trace) } label: { RouteRow(trace: trace) }
                    } else { RouteRow(trace: trace) }
                }
            } else {
                QualityRow("电信，联通，移动", status: status(.routes), value: "")
            }
        } header: { Text("三网线路") } footer: {
            if report?.routes.value != nil { Text("点开查看沿途节点和测试包数量。") }
        }
        .retryMenu(.routes, retryable: retryable.contains(.routes), retry: retry)
    }

    // MARK: NAT and mail port

    private var connectionSection: some View {
        Section {
            if steps.contains(.nat) {
                QualityRow(title: "NAT 类型", subtitle: report?.nat.value?.server, status: status(.nat)) {
                    Text(report?.nat.value?.type.title ?? "").foregroundStyle(.secondary)
                }
                .retryMenu(.nat, retryable: retryable.contains(.nat), retry: retry)
            }
            if steps.contains(.mailPort) {
                QualityRow(title: "邮件端口", subtitle: report?.mailPort.value.map { "TCP \($0.port)，\($0.target)" } ?? "TCP 25", status: status(.mailPort)) {
                    if let probe = report?.mailPort.value {
                        HStack(spacing: 6) { QualityDot(tint: probe.outcome.tint); Text(probe.outcome.title).foregroundStyle(.secondary) }
                    }
                }
                .retryMenu(.mailPort, retryable: retryable.contains(.mailPort), retry: retry)
            }
        } header: { Text("连接") } footer: {
            if let nat = report?.nat.value, let issue = nat.issue { Text(issue.detail ?? issue.title) }
        }
    }

    // MARK: Reputation

    private var reputationSection: some View {
        let records = report?.reputation.value
        return Section {
            if let records {
                ForEach(records) { record in
                    QualityRow(title: record.source, subtitle: [record.family == .v4 ? "IPv4" : "IPv6", record.label].compactMap { $0 }.joined(separator: "，"),
                               status: record.issue.map { .failed($0) } ?? .measured) {
                        HStack(spacing: 6) { QualityDot(tint: record.verdict.tint); Text(record.verdict.title).foregroundStyle(.secondary) }
                    }
                }
            } else {
                QualityRow("各数据源的评级", status: status(.reputation), value: "")
            }
        } header: { Text("IP 信誉") } footer: {
            if let records { Text(reputationNote(records)) }
        }
        .retryMenu(.reputation, retryable: retryable.contains(.reputation), retry: retry)
    }

    private func reputationNote(_ records: [ReputationRecord]) -> String {
        // Clean and low risk read as agreement; a source flagging medium or high risk against the rest does not.
        let flagged = Set(records.filter { $0.issue == nil && $0.verdict != .unknown }.map { $0.verdict == .medium || $0.verdict == .high || $0.verdict == .listed })
        var note = "结果来自各数据源的原始结论"
        if flagged.count > 1 { note += "，各家结论不同，可以对照来源判断" }
        if let time = records.map(\.queriedAt).max() { note += "。查询于 \(time.formatted(date: .omitted, time: .shortened))" }
        return note + "。"
    }

    // MARK: Services

    private var serviceSection: some View {
        let probes = report?.services.value
        return Section {
            if let probes {
                ForEach(probes) { probe in
                    QualityRow(title: probe.name, subtitle: probe.endpoint?.host(), status: probe.issue.map { .failed($0) } ?? .measured) {
                        HStack(spacing: 6) { QualityDot(tint: probe.outcome.tint); Text(probe.outcomeTitle).foregroundStyle(.secondary) }
                    }
                }
            } else {
                QualityRow("网站连通性", status: status(.services), value: "")
            }
        } header: { Text("常用服务") } footer: {
            if let probes, probes.contains(where: { $0.basis == .webPage }) {
                Text("测试范围为网站首页。")
            }
        }
        .retryMenu(.services, retryable: retryable.contains(.services), retry: retry)
    }

    // MARK: Method

    private func methodSection(_ report: NetworkQualityReport) -> some View {
        Section {} footer: {
            Text(methodNote(report))
        }
    }

    private func methodNote(_ report: NetworkQualityReport) -> String {
        var lines: [String] = []
        if let speed = report.speed.value {
            let node = speed.server.location.isEmpty ? speed.server.provider : "\(speed.server.provider) \(speed.server.location)"
            lines.append("测速节点 \(node)。延迟取 \(speed.latencySamples) 次 HTTP 首字节时延的中位数，抖动取相邻样本差值的绝对值再求平均。")
        }
        let egress = [report.ipv4.value, report.ipv6.value].compactMap { $0 }
        for entry in egress {
            let family = entry.family == .v4 ? "IPv4" : "IPv6"
            let attribution = entry.owner.map { "，归属由 \($0.source) 查询" } ?? ""
            lines.append("\(family) 地址由 \(entry.echoSource) 返回\(attribution)。")
        }
        lines.append("开始于 \(report.startedAt.formatted(date: .abbreviated, time: .shortened))。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Rows

private struct EgressRow: View {
    let egress: IPEgress

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(egress.family == .v4 ? "IPv4" : "IPv6").foregroundStyle(Color.seekInk)
                Spacer(minLength: 8)
                if let owner = egress.owner {
                    Text([owner.country, owner.region == owner.city ? nil : owner.region, owner.city].compactMap { $0 }.joined(separator: " "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            // Long IPv6 addresses break only between groups. Copying goes through the menu, which gives the plain address.
            Text(egress.address.replacingOccurrences(of: ":", with: ":\u{200B}"))
                .font(.body.monospaced()).foregroundStyle(Color.seekInk)
                .fixedSize(horizontal: false, vertical: true)
            if let owner = egress.owner {
                let network = [owner.asn.map { "AS\($0)" }, owner.organization].compactMap { $0 }.joined(separator: " ")
                if !network.isEmpty { Text(network).font(.footnote).foregroundStyle(.secondary) }
            } else if let issue = egress.ownerIssue {
                HStack(spacing: 4) {
                    Text("归属：\(issue.title)").font(.footnote).foregroundStyle(.secondary)
                    QualityStatusMark(status: .failed(issue))
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("复制地址", systemImage: "doc.on.doc") { UIPasteboard.general.string = egress.address }
        }
    }
}

/// How the source classifies one address: matched types, then its score.
private struct IPUsageRow: View {
    let profile: IPProfile

    var body: some View {
        let lookup = profile.usage, usage = lookup.result.value
        QualityRow(title: "\(profile.family == .v4 ? "IPv4" : "IPv6") 类型",
                   subtitle: [lookup.source, usage?.scoreTitle].compactMap { $0 }.joined(separator: "，"),
                   status: lookup.result.status) {
            if let usage {
                HStack(spacing: 6) {
                    // Only anonymising types get a hint of colour; datacenter and cellular are plain facts.
                    if usage.tags.contains(where: { [.vpn, .proxy, .tor].contains($0) }) { QualityDot(tint: .orange) }
                    Text(usage.tagsTitle).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The announced prefix and origin network covering one address.
private struct BGPRouteRow: View {
    let profile: IPProfile

    var body: some View {
        let lookup = profile.route, route = lookup.result.value
        QualityRow(title: "\(profile.family == .v4 ? "IPv4" : "IPv6") 路由", subtitle: lookup.source, status: lookup.result.status) {
            if let route {
                if let prefix = route.prefix {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(prefix.replacingOccurrences(of: ":", with: ":\u{200B}"))
                            .font(.subheadline.monospaced()).foregroundStyle(Color.seekInk)
                        if let origins = route.originsTitle { Text(origins).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                    }
                } else {
                    Text("未见公告").foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            if let prefix = route?.prefix { Button("复制地址段", systemImage: "doc.on.doc") { UIPasteboard.general.string = prefix } }
        }
    }
}

private struct RouteRow: View {
    let trace: RouteTrace

    var body: some View {
        QualityRow(title: "\(trace.carrier.title)，\(trace.city)", subtitle: "\(trace.family == .v4 ? "IPv4" : "IPv6")，\(trace.target)",
                   status: trace.issue.map { .failed($0) } ?? .measured) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(trace.averageLatencyMs.map { "\(QualityFormat.ms($0)) ms" } ?? "—").foregroundStyle(Color.seekInk).monospacedDigit()
                if let loss = trace.lossRate {
                    HStack(spacing: 4) {
                        if loss > 0 { QualityDot(tint: loss >= 0.1 ? .red : .orange) }
                        Text("丢包 \(QualityFormat.percent(loss))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - Plumbing

extension EnvironmentValues {
    /// True before the first run, when rows show a dash instead of a waiting state.
    @Entry var qualityIdle = false
}

private extension View {
    /// A long-press "retry" on rows whose step failed or was cancelled.
    @ViewBuilder func retryMenu(_ step: NetworkQualityStep, retryable: Bool, retry: ((NetworkQualityStep) -> Void)?) -> some View {
        if let retry, retryable {
            contextMenu { Button("重试\(step.title)", systemImage: "arrow.clockwise") { retry(step) } }
        } else { self }
    }
}
