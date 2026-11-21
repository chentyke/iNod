import NodeSeekClient
import NodeSeekCore
import SwiftUI

/// Speed tests against carrier nodes, one card per node that has been checked to work.
struct CarrierSpeedView: View {
    @State private var run: CarrierSpeedRun
    @State private var monitor = CurrentNetworkMonitor()

    init(run: CarrierSpeedRun = CarrierSpeedRun()) { _run = State(initialValue: run) }

    var body: some View {
        List {
            ForEach(run.nodes) { node in
                Section {
                    CarrierSpeedCard(
                        node: node, report: run.reports[node.id], isRunning: run.runningID == node.id,
                        canStart: run.runningID == nil && monitor.context.kind != .offline, network: monitor.context,
                        start: { run.start(node) }, cancel: { run.cancel() }
                    )
                } footer: {
                    if node.id == run.nodes.last?.id { Text(Self.footer) }
                }
            }
        }
        .seekGroupedList()
        .navigationTitle("运营商测速").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
        // Leaving the page stops the test, so it never keeps using data out of sight.
        .onDisappear { run.cancel() }
        .onChange(of: run.runningID) { old, new in
            if old != nil, new == nil { AccessibilityNotification.Announcement("测速结束").post() }
        }
    }

    private static let footer = "下载、上传和延迟都在所选节点上测得，与网络检测的 Cloudflare 测速分开。电信和移动节点验证后加入。"
}

// MARK: - Card

private struct CarrierSpeedCard: View {
    let node: CarrierSpeedNode
    let report: CarrierSpeedReport?
    let isRunning: Bool
    let canStart: Bool
    let network: NetworkContext
    let start: () -> Void
    let cancel: () -> Void

    private var name: String { "\(node.city)\(node.carrier.title)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isRunning { running }
            else if let report { finished(report) }
            else { idle }
        }
        // Same trim as the network check header: text leading adds about 2 points above the first line.
        .padding(.top, 6).padding(.bottom, 8)
        .animation(.snappy(duration: 0.25), value: isRunning)
    }

    // Before a run: which node, who runs it, and what it costs on this network.
    private var idle: some View {
        Group {
            HStack(spacing: 12) {
                SeekIconTile(symbol: .inkCarrierSpeed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).foregroundStyle(Color.seekInk)
                    Text(note).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Button("测速", image: .inkStartTest, action: start)
                .buttonStyle(.seekPill).disabled(!canStart)
                .accessibilityIdentifier("carrierSpeed.start")
        }
    }

    private var note: String {
        if network.kind == .offline { return "连接网络后再测速。" }
        var parts = [node.provider, "约消耗 \(Int((Double(node.maximumBytes) / 1_000_000).rounded())) MB 流量"]
        if network.kind == .cellular { parts.append("当前使用蜂窝网络") }
        if network.isConstrained { parts.append("已开启低数据模式") }
        if network.usesVPN { parts.append("经由 VPN，结果反映 VPN 出口") }
        return parts.joined(separator: "，") + "。"
    }

    // During a run: the direction under way, its live figure, progress and the way out.
    private var running: some View {
        let progress: QualityProgress? = if case .running(let progress) = report?.speed { progress } else { nil }
        let stage = progress?.stage
        return Group {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name)，\(stage?.title ?? "正在准备")")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                if let mbps = progress?.currentMbps {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(QualityFormat.mbps(mbps)).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                            .contentTransition(.numericText(value: mbps)).animation(.snappy, value: mbps)
                        Text("Mbps").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                } else {
                    Text(stage.map(Self.direction) ?? "测速").font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(Color.seekInk)
            .accessibilityElement(children: .combine)
            .accessibilityValue("已完成 \(Int((progress?.fraction ?? 0) * 100))%")
            QualityProgressLine(fraction: progress?.fraction ?? 0)
            Button("取消", image: .inkStopTest, action: cancel)
                .buttonStyle(.seekPill(primary: false))
                .accessibilityIdentifier("carrierSpeed.cancel")
        }
    }

    private static func direction(_ stage: QualityStage) -> String {
        switch stage { case .download: "下载"; case .upload: "上传"; default: "延迟" }
    }

    // After a run: both directions, the latency line, what did not finish and why, then the quieter way to run again.
    private func finished(_ report: CarrierSpeedReport) -> some View {
        let speed = report.speed.value
        return Group {
            if let speed {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { figures(speed) }
                    VStack(alignment: .leading, spacing: 12) { figures(speed) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let speed {
                    if let latency = speed.latencyMs {
                        Text("延迟 \(QualityFormat.ms(latency)) ms" + (speed.jitterMs.map { "，抖动 \(QualityFormat.ms($0)) ms" } ?? ""))
                            .font(.subheadline.weight(.medium)).foregroundStyle(Color.seekInk)
                    }
                    ForEach(missing(speed), id: \.self) { line in
                        Text(line).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text(name).font(.headline).foregroundStyle(Color.seekInk)
                    Text(failure(report.speed.status)).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(context(report)).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Button("重新测速", image: .inkRepeatTest, action: start)
                // With results on screen, running again is the quieter choice.
                .buttonStyle(.seekPill(primary: speed == nil)).disabled(!canStart)
                .accessibilityIdentifier("carrierSpeed.restart")
        }
    }

    @ViewBuilder private func figures(_ speed: SpeedMeasurement) -> some View {
        QualityFigure(title: speed.downloadIsEstimate == true ? "下载（估计）" : "下载", value: speed.downloadMbps, unit: "Mbps")
        QualityFigure(title: speed.uploadIsEstimate == true ? "上传（估计）" : "上传", value: speed.uploadMbps, unit: "Mbps")
    }

    /// "上传未测得：超时" for each direction without a figure.
    private func missing(_ speed: SpeedMeasurement) -> [String] {
        let directions = [("下载", speed.downloadMbps), ("上传", speed.uploadMbps), ("延迟", speed.latencyMs)]
        return directions.compactMap { direction, value in
            guard value == nil else { return nil }
            let prefix = "\(direction)未测得"
            let issue = speed.issues.first { $0.detail?.hasPrefix(prefix) == true } ?? speed.issues.first
            guard let issue else { return prefix }
            var reason = (issue.detail ?? "").replacingOccurrences(of: prefix, with: "")
            reason = reason.trimmingCharacters(in: CharacterSet(charactersIn: "，, "))
            return "\(prefix)：\(reason.isEmpty ? issue.title : reason)"
        }
    }

    private func failure(_ status: QualityStatus) -> String {
        if status == .cancelled { return "测速已取消。" }
        return "测速未完成：" + [status.caption, status.issueDetail].compactMap { $0 }.joined(separator: "，") + "。"
    }

    private func context(_ report: CarrierSpeedReport) -> String {
        // The figures replace the title, so the node is named here.
        var parts = ["\(node.provider) \(name)", report.network.kind.title]
        if let bytes = report.speed.value?.bytesTransferred, bytes > 0 { parts.append("用了 \(QualityFormat.bytes(bytes))") }
        parts.append(report.startedAt.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: "，")
    }
}

// MARK: - Run

/// Drives the carrier speed page. One node runs at a time so tests do not share the line.
@MainActor @Observable
final class CarrierSpeedRun {
    private(set) var reports: [CarrierSpeedNode.ID: CarrierSpeedReport]
    private(set) var runningID: CarrierSpeedNode.ID?
    @ObservationIgnored private nonisolated(unsafe) var task: Task<Void, Never>?
    @ObservationIgnored let tester: any CarrierSpeedTesting

    init(tester: any CarrierSpeedTesting = QualityServices.carrierSpeed, reports: [CarrierSpeedNode.ID: CarrierSpeedReport] = [:]) {
        self.tester = tester; self.reports = reports
    }
    deinit { task?.cancel() }

    var nodes: [CarrierSpeedNode] { tester.nodes }

    func start(_ node: CarrierSpeedNode) {
        cancel()
        runningID = node.id
        let stream = tester.run(node)
        task = Task { [weak self] in
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { return }
                self.reports[node.id] = snapshot
            }
            guard let self, !Task.isCancelled else { return }
            // A stream that ends early leaves the run unfinished; treat it like a cancel so nothing spins forever.
            if let report = self.reports[node.id], !report.isFinished { self.reports[node.id] = report.cancellingUnfinished() }
            self.runningID = nil
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        if let id = runningID, let report = reports[id] { reports[id] = report.cancellingUnfinished() }
        runningID = nil
    }
}

extension QualityServices {
    static var carrierSpeed: any CarrierSpeedTesting {
        guard QualityServices.usesSamples else { return LiveCarrierSpeedTester() }
        let scenario = UserDefaults.standard.string(forKey: "qualitySample").flatMap(QualitySampleScenario.init) ?? .complete
        return SampleCarrierSpeedTester(scenario: scenario, pace: pace)
    }
}

#Preview("Idle") { NavigationStack { CarrierSpeedView(run: CarrierSpeedRun(tester: SampleCarrierSpeedTester())) } }
#Preview("Finished") {
    NavigationStack {
        CarrierSpeedView(run: CarrierSpeedRun(tester: SampleCarrierSpeedTester(), reports: [CarrierSpeedNode.sample.id: .sample(.complete)]))
    }
}
#Preview("Upload failed") {
    NavigationStack {
        CarrierSpeedView(run: CarrierSpeedRun(tester: SampleCarrierSpeedTester(), reports: [CarrierSpeedNode.sample.id: .sample(.partialFailure)]))
    }
}
