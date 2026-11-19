import Foundation
import NodeSeekClient
import NodeSeekCore
import SwiftUI

extension QualityServices {
    static var streaming: any StreamingChecking {
        guard ProcessInfo.processInfo.arguments.contains("--ui-test-offline") else { return LiveStreamingChecker() }
        let pace = UserDefaults.standard.double(forKey: "qualityPace")
        return SampleStreamingChecker(pace: pace > 0 ? pace : 1)
    }
}

/// Drives the streaming screen: the sample run and the latest playback attempt per platform.
@MainActor @Observable
final class StreamingCheckRun {
    private(set) var checks: [StreamingSampleCheck]?
    private(set) var isRunning = false
    var playback: [StreamingPlatform: QualityResult<StreamingPlaybackOutcome>] = [:]
    @ObservationIgnored let checker: any StreamingChecking
    @ObservationIgnored private nonisolated(unsafe) var task: Task<Void, Never>?

    init(checker: any StreamingChecking = QualityServices.streaming) { self.checker = checker }
    deinit { task?.cancel() }

    func start() {
        task?.cancel()
        isRunning = true
        let stream = checker.run()
        task = Task { [weak self] in
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { return }
                self.checks = snapshot
            }
            guard let self, !Task.isCancelled else { return }
            self.finishUnfinished()
            self.isRunning = false
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        finishUnfinished()
        isRunning = false
    }

    private func finishUnfinished() {
        checks = checks?.map { check in
            var check = check
            check.result = check.result.cancellingUnfinished
            return check
        }
    }
}

/// Public samples on five platforms, the official players for the two that embed, and YouTube's region rule.
struct StreamingCheckView: View {
    @State private var run: StreamingCheckRun
    @State private var playing: PlaybackAttempt?
    /// The run's exit country, used to prefill the region form.
    let countryCode: String?

    init(countryCode: String? = nil, run: StreamingCheckRun = StreamingCheckRun()) {
        self.countryCode = countryCode
        _run = State(initialValue: run)
    }

    var body: some View {
        List {
            Section { StreamingHeader(run: run) }
            Section {
                ForEach(run.checks ?? run.checker.platforms.map { .init(platform: $0, result: .pending) }) { check in
                    SampleRow(check: check)
                }
            } header: { Text("样片") } footer: {
                Text("结果只说明本次请求取得了哪种信息，不代表付费内容可以播放，也不代表地区片库完整。")
            }
            .environment(\.qualityIdle, run.checks == nil)
            Section {
                ForEach(StreamingPlatform.playable.filter(run.checker.platforms.contains)) { platform in
                    Button { start(platform) } label: { PlaybackRow(platform: platform, result: run.playback[platform]) }
                        // Without this the separator lines up with the trailing "试播" text instead of the title.
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                        .disabled(run.checker.playbackCheck(for: platform) == nil)
                        .accessibilityIdentifier("streaming.play.\(platform.rawValue)")
                }
            } header: { Text("播放器") } footer: {
                Text("在官方嵌入播放器里静音播放样片。进入播放状态且播放时间持续前进，才算已播放。")
            }
            Section {
                NavigationLink {
                    YouTubeRegionView(checker: run.checker, countryCode: countryCode)
                } label: {
                    QualityRow(title: "YouTube 地区规则", subtitle: "查询某部视频对某个国家发布的规则", status: .measured) { EmptyView() }
                }
                .accessibilityIdentifier("streaming.region")
            }
        }
        .seekGroupedList()
        .navigationTitle("流媒体").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
        .sheet(item: $playing) { attempt in
            StreamingPlayerSheet(check: attempt.check) { run.playback[attempt.check.platform] = $0 }
        }
        .onChange(of: run.isRunning) { _, running in
            if !running, run.checks != nil { AccessibilityNotification.Announcement("检查结束").post() }
        }
    }

    private func start(_ platform: StreamingPlatform) {
        guard let check = run.checker.playbackCheck(for: platform) else { return }
        run.playback[platform] = .running(.init())
        playing = PlaybackAttempt(check: check)
    }
}

private struct PlaybackAttempt: Identifiable {
    let id = UUID()
    let check: any StreamingPlaybackChecking
}

// MARK: - Header

private struct StreamingHeader: View {
    let run: StreamingCheckRun

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Color.seekInk).contentTransition(.opacity)
                Text(note).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if run.isRunning {
                QualityProgressLine(fraction: fraction)
                Button("取消", image: .inkStopTest) { run.cancel() }
                    .buttonStyle(.seekPill(primary: false))
                    .accessibilityIdentifier("streaming.cancel")
            } else if run.checks == nil {
                Button("开始检查", image: .inkStartTest) { run.start() }
                    .buttonStyle(.seekPill)
                    .accessibilityIdentifier("streaming.start")
            } else {
                Button("重新检查", image: .inkRepeatTest) { run.start() }
                    .buttonStyle(.seekPill(primary: false))
                    .accessibilityIdentifier("streaming.restart")
            }
        }
        // Same trim as the network check header, so glyphs sit as far from the top as the button from the bottom.
        .padding(.top, 6).padding(.bottom, 8)
        .animation(.snappy(duration: 0.25), value: run.isRunning)
    }

    private var finished: [StreamingSampleCheck] { (run.checks ?? []).filter { $0.result.status.isFinished } }
    private var fraction: Double {
        guard let checks = run.checks, !checks.isEmpty else { return 0 }
        return Double(finished.count) / Double(checks.count)
    }

    private var title: String {
        if run.isRunning { return "正在请求样片" }
        guard let checks = run.checks else { return "流媒体样片" }
        let returned = checks.filter { $0.result.value == .titlePage || $0.result.value == .embedMetadata }.count
        return returned == 0 ? "没有平台返回片名或嵌入信息" : "\(returned) 个平台返回了片名或嵌入信息"
    }

    private var note: String {
        if run.isRunning { return "已完成 \(finished.count) / \(run.checks?.count ?? 0)" }
        guard let checks = run.checks else {
            return "从当前网络请求五个平台的公开样片，看能取得哪种信息。流量很小，不需要登录。"
        }
        let time = checks.compactMap(\.queriedAt).max() ?? .now
        let cancelled = checks.contains { $0.result == .cancelled } ? "，部分已取消" : ""
        return "查询于 \(time.formatted(date: .omitted, time: .shortened))\(cancelled)。"
    }
}

// MARK: - Rows

private struct SampleRow: View {
    let check: StreamingSampleCheck

    var body: some View {
        QualityRow(title: check.platform.title, subtitle: subtitle, status: check.result.status) {
            // The verdict stays on one line; a long sample title wraps instead.
            if let evidence = check.result.value {
                HStack(spacing: 6) { QualityDot(tint: evidence.tint); Text(evidence.title).foregroundStyle(.secondary) }.fixedSize()
            }
        }
    }

    /// The sample, plus the HTTP status when it is the reason for the outcome.
    private var subtitle: String? {
        var parts = [check.sampleTitle].compactMap { $0 }
        if let status = check.httpStatus, status != 200 { parts.append("HTTP \(status)") }
        if let detail = check.result.status.issueDetail { parts.append(detail) }
        return parts.isEmpty ? nil : parts.joined(separator: "，")
    }
}

private struct PlaybackRow: View {
    let platform: StreamingPlatform
    let result: QualityResult<StreamingPlaybackOutcome>?

    var body: some View {
        // A row with no attempt yet shows what tapping it does.
        QualityRow(title: platform.title, subtitle: "官方播放器，静音", status: result?.status ?? .measured) {
            if let outcome = result?.value {
                HStack(spacing: 6) { QualityDot(tint: outcome.tint); Text(outcome.title).foregroundStyle(.secondary) }.fixedSize()
            } else {
                HStack(spacing: 4) { Image(.inkPlayVideo).font(.caption2); Text("试播") }
                    .foregroundStyle(.secondary).fixedSize()
            }
        }
        // A button row would tint every secondary text; this row reads like the others.
        .foregroundStyle(Color.seekInk)
    }
}

extension StreamingEvidence {
    var tint: Color {
        switch self {
        case .titlePage, .embedMetadata: .green
        case .legallyRestricted: .orange
        case .authenticationRequired, .redirected, .undetermined: .secondary
        }
    }
}

extension StreamingPlaybackOutcome {
    var tint: Color {
        switch self { case .played: .green; case .autoplayBlocked, .playerError: .orange }
    }
}

extension YouTubeRegionRule {
    var tint: Color {
        switch self { case .allowed: .green; case .blocked: .orange; case .noPublishedRule, .undetermined: .secondary }
    }
}

#Preview("Idle") { NavigationStack { StreamingCheckView(countryCode: "US", run: StreamingCheckRun(checker: SampleStreamingChecker(pace: 0.3))) } }
