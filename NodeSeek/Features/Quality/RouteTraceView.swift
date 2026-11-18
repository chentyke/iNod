import NodeSeekCore
import SwiftUI

/// The hops on the way to one carrier's test node. A hop that never answered is listed in its place,
/// and the hops after it still show.
struct RouteTraceView: View {
    let trace: RouteTrace

    var body: some View {
        List {
            Section {
                LabeledContent("目标", value: trace.target).monospacedDigit()
                LabeledContent("地址类型", value: trace.family == .v4 ? "IPv4" : "IPv6")
                LabeledContent("平均延迟", value: trace.averageLatencyMs.map { "\(QualityFormat.ms($0)) ms" } ?? "—")
                LabeledContent("丢包", value: trace.lossRate.map { "\(QualityFormat.percent($0))（收到 \(trace.received) / \(trace.sent)）" } ?? "—")
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
        .navigationTitle("\(trace.carrier.title)，\(trace.city)").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
    }
}

private struct HopRow: View {
    let hop: RouteHop

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(hop.index)").font(.subheadline.monospacedDigit()).foregroundStyle(.tertiary)
                .frame(minWidth: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                if let address = hop.address {
                    Text(address).font(.subheadline.monospaced()).foregroundStyle(Color.seekInk).textSelection(.enabled)
                    if let owner = hop.owner { Text(owner).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text("无回应").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let rtt = hop.rttMs { Text("\(QualityFormat.ms(rtt)) ms").font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        if case .measured(let traces) = NetworkQualityReport.sample(.partialFailure).routes { RouteTraceView(trace: traces[0]) }
    }
}
