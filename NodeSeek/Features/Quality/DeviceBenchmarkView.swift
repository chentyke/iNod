import NodeSeekCore
import SwiftUI
import UIKit

struct DeviceBenchmarkView: View {
    @State private var run: DeviceBenchmarkRun
    @State private var thermal = ThermalLevel(ProcessInfo.processInfo.thermalState)

    init(run: DeviceBenchmarkRun = DeviceBenchmarkRun()) { _run = State(initialValue: run) }

    var body: some View {
        List {
            // Same trim as the network check's header: equal glyph-to-edge space top and bottom.
            Section { header.padding(.top, 6).padding(.bottom, 8) }
            resultSections
            if !run.history.isEmpty { historySection }
        }
        .seekGroupedList()
        .navigationTitle("本机性能").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermal = ThermalLevel(ProcessInfo.processInfo.thermalState)
        }
        .onChange(of: run.report?.runningStep) { _, step in
            if let step { AccessibilityNotification.Announcement("正在测试\(step.title)").post() }
        }
        .onChange(of: run.isRunning) { _, running in
            if !running, run.report != nil { AccessibilityNotification.Announcement("测试结束").post() }
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if run.isRunning, let report = run.report { running(report) }
            else if let report = run.report { finished(report) }
            else { idle }
        }
        .animation(.snappy(duration: 0.25), value: run.isRunning)
    }

    private var idle: some View {
        Group {
            HStack(spacing: 12) {
                SeekIconTile(symbol: .inkDevice)
                VStack(alignment: .leading, spacing: 2) {
                    Text(UIDevice.current.model + "，iOS " + UIDevice.current.systemVersion).font(.headline).foregroundStyle(Color.seekInk)
                    Text("温度\(thermal.title)。可离线测试，临时使用 \(QualityFormat.bytes(run.benchmark.scratchBytes)) 存储空间。")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            if thermal >= .serious {
                Text("设备现在较热，成绩可能偏低。可以等它凉下来再测。").font(.footnote).foregroundStyle(.secondary)
            }
            Button("开始测试", image: .inkStartBench) { run.start() }
                .buttonStyle(.seekPill).accessibilityIdentifier("benchmark.start")
        }
    }

    private func running(_ report: DeviceBenchmarkReport) -> some View {
        let step = report.runningStep
        return Group {
            VStack(alignment: .leading, spacing: 2) {
                Text("正在测试").font(.subheadline).foregroundStyle(.secondary)
                Text(step?.title ?? "准备中").font(.system(.largeTitle, design: .rounded).weight(.semibold)).foregroundStyle(Color.seekInk)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue("已完成 \(Int(overall(report) * 100))%")
            QualityProgressLine(fraction: overall(report))
            Text("测试时请保持 App 在前台。").font(.footnote).foregroundStyle(.secondary)
            Button("取消", image: .inkStopTest) { run.cancel() }
                .buttonStyle(.seekPill(primary: false)).accessibilityIdentifier("benchmark.cancel")
        }
    }

    private func overall(_ report: DeviceBenchmarkReport) -> Double {
        let steps = DeviceBenchmarkStep.allCases
        return steps.reduce(0.0) { sum, step in
            switch report.status(of: step) {
            case .running(let progress): sum + (progress.fraction ?? 0)
            case let status where status.isFinished: sum + 1
            default: sum
            }
        } / Double(steps.count)
    }

    private func finished(_ report: DeviceBenchmarkReport) -> some View {
        Group {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { figures(report) }
                VStack(alignment: .leading, spacing: 12) { figures(report) }
            }
            Text(context(report)).font(.footnote).foregroundStyle(.secondary)
            if let issue = report.cleanupIssue { Text(issue.detail ?? issue.title).font(.footnote).foregroundStyle(.secondary) }
            if report.mayBeThrottled {
                Text("测试时设备较热，系统可能已降低性能，成绩可能偏低。").font(.footnote).foregroundStyle(.secondary)
            }
            Button(report.isComplete ? "再测一次" : "重新测试", image: .inkRepeatBench) { run.start() }
                .buttonStyle(.seekPill(primary: false)).accessibilityIdentifier("benchmark.restart")
        }
    }

    @ViewBuilder private func figures(_ report: DeviceBenchmarkReport) -> some View {
        QualityFigure(title: "单核", value: report.cpuSingle.value.map { Double($0.score) }, unit: "分", format: Self.score)
        QualityFigure(title: report.cpuMulti.value.map { "多核，\($0.threads) 线程" } ?? "多核", value: report.cpuMulti.value.map { Double($0.score) }, unit: "分", format: Self.score)
    }

    private static func score(_ value: Double) -> String { Int(value).formatted(.number.grouping(.never)) }

    private func context(_ report: DeviceBenchmarkReport) -> String {
        [report.device.model, "iOS \(report.device.systemVersion)",
         "温度\(report.thermalAtStart.title)" + (report.thermalAtEnd.map { $0 == report.thermalAtStart ? "" : " → \($0.title)" } ?? ""),
         report.lowPowerMode == true ? "低电量模式" : nil,
         report.startedAt.formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: "，")
    }

    // MARK: Results

    @ViewBuilder private var resultSections: some View {
        let report = run.report
        // Once both scores are in, the header shows them; the rows stay only while they have a state to report.
        if report?.cpuSingle.value == nil || report?.cpuMulti.value == nil {
            Section("CPU") {
                cpuRow("单核", report?.cpuSingle)
                cpuRow("多核", report?.cpuMulti)
            }
        }
        Section {
            storageRows("顺序读写", subtitle: "1 MiB 块", report?.storageSequential, iops: false)
            storageRows("随机读写", subtitle: "4 KiB 块", report?.storageRandom, iops: true)
        } header: { Text("存储") } footer: {
            if let report, report.finishedAt != nil, report.cpuSingle.value != nil {
                Text("CPU 分数为每秒完成的 1 MiB SHA-256 计算次数。比较成绩时请使用同一测试版本（\(report.method)）。")
            }
        }
        .environment(\.qualityIdle, report == nil)
    }

    private func cpuRow(_ title: String, _ result: QualityResult<CPUScore>?) -> some View {
        QualityRow(title, subtitle: result?.value.map { "\($0.threads) 线程" }, status: result?.status ?? .pending,
                   value: result?.value.map { Self.score(Double($0.score)) + " 分" } ?? "")
            .environment(\.qualityIdle, result == nil)
    }

    private func storageRows(_ title: String, subtitle: String, _ result: QualityResult<StorageThroughput>?, iops: Bool) -> some View {
        QualityRow(title: title, subtitle: subtitle, status: result?.status ?? .pending) {
            if let value = result?.value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("读 \(Self.mbps(value.readMBps))，写 \(Self.mbps(value.writeMBps))").foregroundStyle(.secondary).monospacedDigit()
                    if iops, let read = value.readIOPS, let write = value.writeIOPS {
                        Text("\(Self.count(read)) / \(Self.count(write)) IOPS").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .environment(\.qualityIdle, result == nil)
    }

    private static func mbps(_ value: Double) -> String { value.formatted(.number.grouping(.never).precision(.fractionLength(value >= 100 ? 0 : 1))) + " MB/s" }
    private static func count(_ value: Int) -> String { value.formatted(.number.grouping(.never)) }

    // MARK: History

    private var historySection: some View {
        Section {
            ForEach(run.history) { past in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("单核 \(past.cpuSingle.value.map { Self.score(Double($0.score)) } ?? "—")，多核 \(past.cpuMulti.value.map { Self.score(Double($0.score)) } ?? "—")")
                            .foregroundStyle(Color.seekInk).monospacedDigit()
                        Spacer(minLength: 8)
                        if past.id == run.report?.id { Text("本次").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                    }
                    Text([past.startedAt.formatted(date: .abbreviated, time: .shortened),
                          past.storageSequential.value.map { "读 \(Self.mbps($0.readMBps))" },
                          past.mayBeThrottled ? "较热" : nil].compactMap { $0 }.joined(separator: "，"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .swipeActions { Button("删除", image: .inkDeleteRun, role: .destructive) { run.forget(past) } }
            }
        } header: { Text("历史成绩") } footer: {
            Text("只保存在这台设备上，最多 20 次。左滑可以删除。")
        }
    }
}

private extension ThermalLevel {
    init(_ state: ProcessInfo.ThermalState) {
        switch state { case .nominal: self = .nominal; case .fair: self = .fair; case .serious: self = .serious; case .critical: self = .critical; @unknown default: self = .fair }
    }
}

#Preview { NavigationStack { DeviceBenchmarkView() } }
