import NodeSeekCore
import SwiftUI

struct NetworkQualityView: View {
    @State private var run: NetworkQualityRun
    @State private var monitor = CurrentNetworkMonitor()
    @AppStorage("quality.hidesAddresses") private var hidesAddresses = true

    init(run: NetworkQualityRun = NetworkQualityRun()) { _run = State(initialValue: run) }

    var body: some View {
        List {
            Section {
                NetworkQualityHeader(run: run, network: run.report?.network ?? monitor.context, estimatedUsage: run.tester.estimatedUsage)
            }
            NetworkQualityReportSections(report: run.report, steps: run.report?.includedSteps ?? run.tester.supportedSteps, retry: run.isRunning ? nil : { run.retry([$0]) })
        }
        .seekGroupedList()
        .navigationTitle("网络检测").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let report = run.report, !run.isRunning {
                ToolbarItem(placement: .topBarTrailing) { NetworkQualityShareMenu(report: report, hidesAddresses: $hidesAddresses) }
            }
        }
        .onChange(of: run.report?.runningStep) { _, step in
            if let step { AccessibilityNotification.Announcement("正在检测\(step.title)").post() }
        }
        .onChange(of: run.isRunning) { _, running in
            if !running, run.report != nil { AccessibilityNotification.Announcement("检测结束").post() }
        }
    }
}

// MARK: - Header

private struct NetworkQualityHeader: View {
    let run: NetworkQualityRun
    let network: NetworkContext
    let estimatedUsage: ClosedRange<Int64>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if run.isRunning, let report = run.report { running(report) }
            else if let report = run.report { finished(report) }
            else { idle }
        }
        // Text leading adds about 2 points above the first line; trim it so the glyphs sit as far from the top
        // of the card as the button does from the bottom.
        .padding(.top, 6).padding(.bottom, 8)
        .animation(.snappy(duration: 0.25), value: run.isRunning)
    }

    // Before the first run: what will be tested on, and what it costs.
    private var idle: some View {
        Group {
            HStack(spacing: 12) {
                SeekIconTile(symbol: network.kind.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(network.kind.title).font(.headline).foregroundStyle(Color.seekInk)
                    Text(networkNote).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Button { run.start() } label: {
                SeekPillLabel(title: "开始检测", symbol: .inkStartTest)
            }
                .buttonStyle(.seekPill).disabled(network.kind == .offline)
                .accessibilityIdentifier("quality.start")
        }
    }

    private var networkNote: String {
        if network.kind == .offline { return "连接网络后再开始检测。" }
        var parts = ["约消耗 \(QualityFormat.usage(estimatedUsage)) 流量"]
        if network.isConstrained { parts.append("已开启低数据模式") }
        if network.usesVPN { parts.append("经由 VPN，结果反映 VPN 出口") }
        return parts.joined(separator: "，") + "。"
    }

    // During a run: the step under way, its live figure, overall progress and the way out.
    private func running(_ report: NetworkQualityReport) -> some View {
        let step = report.runningStep
        let progress: QualityProgress? = if case .running(let progress) = step.map(report.status(of:)) { progress } else { nil }
        return Group {
            VStack(alignment: .leading, spacing: 2) {
                Text(progress?.stage?.title ?? step.map { "正在检测\($0.title)" } ?? "正在准备")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                if let mbps = progress?.currentMbps {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(QualityFormat.mbps(mbps)).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                            .contentTransition(.numericText(value: mbps)).animation(.snappy, value: mbps)
                        Text("Mbps").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                } else {
                    Text(step?.title ?? "网络检测").font(.system(.largeTitle, design: .rounded).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(Color.seekInk)
            .accessibilityElement(children: .combine)
            .accessibilityValue("已完成 \(Int(overall(report) * 100))%")
            QualityProgressLine(fraction: overall(report))
            Button { run.cancel() } label: {
                SeekPillLabel(title: "取消", symbol: .inkStopTest, primary: false)
            }
                .buttonStyle(.seekPill(primary: false))
                .accessibilityIdentifier("quality.cancel")
        }
    }

    /// Speed takes most of a run's time, so it counts for more of the bar than the quick lookups.
    private func overall(_ report: NetworkQualityReport) -> Double {
        let steps = report.includedSteps
        func weight(_ step: NetworkQualityStep) -> Double { step == .speed ? 4 : 1 }
        let total = steps.map(weight).reduce(0, +)
        guard total > 0 else { return 0 }
        let done = steps.reduce(0.0) { sum, step in
            switch report.status(of: step) {
            case .running(let progress): sum + (progress.fraction ?? 0) * weight(step)
            case let status where status.isFinished: sum + weight(step)
            default: sum
            }
        }
        return done / total
    }

    // After a run: the two numbers people came for, where they were measured, and what to do next.
    private func finished(_ report: NetworkQualityReport) -> some View {
        let speed = report.speed.value
        return Group {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { figures(speed) }
                VStack(alignment: .leading, spacing: 12) { figures(speed) }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let speed, let latency = speed.latencyMs {
                    Text("延迟 \(QualityFormat.ms(latency)) ms" + (speed.jitterMs.map { "，抖动 \(QualityFormat.ms($0)) ms" } ?? ""))
                        .font(.subheadline.weight(.medium)).foregroundStyle(Color.seekInk)
                } else if report.speed.status != .measured {
                    Text("速度未测得：\(report.speed.status.caption)").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(context(report, speed)).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            actions
        }
    }

    @ViewBuilder private func figures(_ speed: SpeedMeasurement?) -> some View {
        QualityFigure(title: speed?.downloadIsEstimate == true ? "下载（估计）" : "下载", value: speed?.downloadMbps, unit: "Mbps")
        QualityFigure(title: speed?.uploadIsEstimate == true ? "上传（估计）" : "上传", value: speed?.uploadMbps, unit: "Mbps")
    }

    private func context(_ report: NetworkQualityReport, _ speed: SpeedMeasurement?) -> String {
        var parts = [report.network.kind.title]
        if let speed { parts.append("\(speed.server.provider) \(speed.server.location)") }
        parts.append(report.startedAt.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: "，")
    }

    @ViewBuilder private var actions: some View {
        let retryable = run.retryableSteps
        HStack(spacing: 10) {
            if !retryable.isEmpty {
                // After a cancel nothing failed; the rest simply never ran.
                let resumes = run.report.map { report in retryable.allSatisfy { report.status(of: $0) == .cancelled } } ?? false
                Button { run.retry(retryable) } label: {
                    SeekPillLabel(
                        title: resumes ? "继续剩余 \(retryable.count) 项" : "重试 \(retryable.count) 项",
                        symbol: resumes ? .inkResumeTest : .inkRetryStep
                    )
                }
                    .buttonStyle(.seekPill)
                    .accessibilityIdentifier("quality.retry")
            }
            Button { run.start() } label: {
                SeekPillLabel(title: "重新检测", symbol: .inkRepeatTest, primary: false)
            }
                // The results are the point of the page now; running again is the quieter choice.
                .buttonStyle(.seekPill(primary: false))
                .accessibilityIdentifier("quality.restart")
        }
    }
}

// MARK: - Share

private struct NetworkQualityShareMenu: View {
    let report: NetworkQualityReport
    @Binding var hidesAddresses: Bool

    var body: some View {
        let text = report.sharedText(hidingAddresses: hidesAddresses)
        Menu {
            ShareLink(item: text, preview: SharePreview("iNod 网络检测")) { Label("分享报告", image: .inkShareReport) }
            Button("复制报告", image: .inkCopyReport) { UIPasteboard.general.string = text }
            Divider()
            Toggle(isOn: $hidesAddresses) { Label("隐藏完整 IP", image: .inkMaskAddress) }
        } label: {
            Label("分享", image: .inkShareReport)
        }
        .accessibilityIdentifier("quality.share")
    }
}

#Preview("Idle") { NavigationStack { NetworkQualityView() } }
#Preview("Finished") { NavigationStack { NetworkQualityView(run: NetworkQualityRun(report: .sample(.complete))) } }
#Preview("Partial") { NavigationStack { NetworkQualityView(run: NetworkQualityRun(report: .sample(.partialFailure))) } }
