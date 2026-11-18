import NodeSeekClient
import NodeSeekCore
import SwiftUI

/// Probes on each Chinese carrier trace toward an address the reader types in, usually their server.
/// Globalping publishes the target and the results, so the test only runs after the reader confirms that,
/// and the reader's own address is only ever filled in by tapping it.
struct ReturnRouteView: View {
    /// Addresses from the current report, offered as quick fills.
    var suggestions: [IPEgress] = []
    var tester: any ReturnRouteTesting = QualityServices.returnRoute

    @State private var text = ""
    @State private var confirming = false
    @State private var task: Task<Void, Never>?
    @State private var tracing: ReturnRouteTarget?
    @State private var routes: [ReturnRoute]?
    @FocusState private var editing: Bool

    private static let terms = URL(string: "https://globalping.io/terms/terms-of-use.md")!

    private var parsed: Result<ReturnRouteTarget, ReturnRouteTarget.Problem> { ReturnRouteTarget.parse(text) }
    private var target: ReturnRouteTarget? { try? parsed.get() }
    private var problem: String? { if case .failure(let problem) = parsed { problem.message } else { nil } }

    var body: some View {
        List {
            targetSection
            // The pill stands on its own between the target and the results. The top padding evens out the
            // visual gaps: the footer above ends in descender space, the header below starts at its cap height.
            Section { actions.padding(.top, 6) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            resultSection
        }
        .seekGroupedList()
        .navigationTitle("回程线路").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
        .onDisappear { task?.cancel() }
    }

    // MARK: Target

    private var targetSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                // Long IPv6 addresses wrap rather than scroll out of sight.
                TextField("IPv4 或 IPv6 地址", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.body.monospacedDigit()).foregroundStyle(Color.seekInk)
                    .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done).focused($editing)
                    // A multi-line field takes Return as a newline; treat it as done instead.
                    .onChange(of: text) { _, new in
                        if new.contains("\n") { text = new.replacingOccurrences(of: "\n", with: ""); editing = false }
                    }
                    .disabled(task != nil)
                    .accessibilityIdentifier("returnRoute.target")
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("returnRoute.problem")
                }
            }
            if task == nil, !suggestions.isEmpty {
                HStack(spacing: 8) {
                    Text("填入本机出口").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    ForEach(suggestions, id: \.address) { egress in
                        Button(egress.family == .v4 ? "IPv4" : "IPv6") { text = egress.address; editing = false }
                            .font(.subheadline.weight(.medium)).foregroundStyle(Color.seekInk)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .overlay { Capsule().strokeBorder(Color.seekHairline, lineWidth: 0.5) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("填入本机 \(egress.family == .v4 ? "IPv4" : "IPv6") 出口地址")
                    }
                }
            }
        } header: { Text("目标地址") } footer: {
            Text("测试由 Globalping 的公开节点完成，目标地址和结果会公开，任何人都能查到。请只填可以公开的地址，比如你的服务器。[使用条款](\(Self.terms.absoluteString))")
        }
    }

    // MARK: Start and cancel

    @ViewBuilder private var actions: some View {
        if task != nil {
            Button("取消", systemImage: "xmark") { task?.cancel() }
                .buttonStyle(.seekPill(primary: false))
                .accessibilityIdentifier("returnRoute.cancel")
        } else {
            Button(routes == nil ? "开始测试" : "重新测试", systemImage: "play.fill") { editing = false; confirming = true }
                // Once results are in they are the point of the page; running again is the quieter choice.
                .buttonStyle(.seekPill(primary: routes == nil)).disabled(target == nil)
                .accessibilityIdentifier("returnRoute.start")
                // Anchored to the button, so the question appears where the reader tapped.
                .confirmationDialog("公开测试这个地址？", isPresented: $confirming, titleVisibility: .visible, presenting: target) { target in
                    Button("公开并开始测试") { start(target) }
                    Button("取消", role: .cancel) {}
                } message: { target in
                    Text("Globalping 会公开 \(target.address) 和测试结果，任何人都能查到。")
                }
        }
    }

    private func start(_ target: ReturnRouteTarget) {
        tracing = target
        routes = nil
        task = Task {
            let result = await tester.trace(to: target)
            routes = result
            tracing = nil
            task = nil
            AccessibilityNotification.Announcement("回程测试结束").post()
        }
    }

    // MARK: Results

    private var resultSection: some View {
        Section {
            if let routes {
                ForEach(routes) { route in
                    if let trace = route.result.value, !trace.hops.isEmpty {
                        NavigationLink { ReturnRouteTraceView(route: route, trace: trace) } label: { ReturnRouteRow(route: route) }
                    } else { ReturnRouteRow(route: route) }
                }
            } else {
                ForEach(ChinaCarrier.allCases, id: \.self) { carrier in
                    QualityRow(carrier.title, status: tracing == nil ? .pending : .running(.init(stage: .tracing)), value: "")
                }
                .environment(\.qualityIdle, tracing == nil)
            }
        } header: { Text("三网回程") } footer: {
            if tracing != nil {
                Text("远端节点通常在 20 秒内完成。")
            } else if let first = routes?.first {
                Text("三网节点向 \(first.target.address) 发起路由追踪，测的是回到这个地址的线路。「无回应」的节点只是不回复测试包，不代表线路中断。测于 \(first.startedAt.formatted(date: .omitted, time: .shortened))。")
            }
        }
    }
}

private struct ReturnRouteRow: View {
    let route: ReturnRoute

    var body: some View {
        if let trace = route.result.value {
            QualityRow(title: route.carrier.title, subtitle: "\(trace.probeCity)，AS\(route.probeASN)，\(trace.hops.count) 跳", status: .measured) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(trace.lastLatencyMs.map { "\(QualityFormat.ms($0)) ms" } ?? "—").foregroundStyle(Color.seekInk).monospacedDigit()
                    HStack(spacing: 4) {
                        QualityDot(tint: trace.reachedTarget ? .green : .secondary)
                        Text(trace.reachedTarget ? "目标已回应" : "目标未回应").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            // The shared wording for `.unavailable` names a lookup service; here it means no probe answered.
            let status = route.result.status
            QualityRow(title: route.carrier.title, subtitle: status.issueDetail, status: .measured) {
                HStack(spacing: 6) {
                    Text({ if case .unavailable = status { "未测得" } else { status.caption } }()).font(.subheadline).foregroundStyle(.secondary)
                    QualityStatusMark(status: status)
                }
            }
        }
    }
}

/// The hops from one carrier's probe to the target, in the same style as the outbound traces.
struct ReturnRouteTraceView: View {
    let route: ReturnRoute
    let trace: ReturnRoute.Trace

    var body: some View {
        List {
            Section {
                LabeledContent("目标", value: route.target.address).monospacedDigit()
                LabeledContent("地址类型", value: route.target.family == .v4 ? "IPv4" : "IPv6")
                LabeledContent("测试节点", value: "\(trace.probeCity)，AS\(route.probeASN)")
                LabeledContent("末跳延迟", value: trace.lastLatencyMs.map { "\(QualityFormat.ms($0)) ms" } ?? "—")
                LabeledContent("目标回应", value: trace.reachedTarget ? "已回应" : "未回应")
            }
            Section {
                ForEach(trace.hops) { HopRow(hop: $0) }
            } header: { Text("沿途节点") } footer: {
                if trace.hops.contains(where: { $0.address == nil }) {
                    Text("「无回应」的节点没有回复测试包，通常是设备设置了不回应，并不代表线路在这里中断。")
                }
            }
        }
        .seekGroupedList()
        .navigationTitle("\(route.carrier.title)回程").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
    }
}

extension QualityServices {
    static var returnRoute: any ReturnRouteTesting {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-offline") { return SampleReturnRouteTester(pace: pace) }
        return LiveReturnRouteTester()
    }
}

#Preview("Empty") { NavigationStack { ReturnRouteView(suggestions: [NetworkQualityReport.sample(.complete).ipv4.value].compactMap { $0 }) } }
#Preview("Hops") {
    let route = SampleReturnRouteTester.routes(to: .init(family: .v4, address: "203.0.113.80"))[1]
    NavigationStack { ReturnRouteTraceView(route: route, trace: route.result.value!) }
}
