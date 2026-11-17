import NodeSeekCore
import SwiftUI

/// A small mark for a step that has no value to show yet, or never will.
struct QualityStatusMark: View {
    let status: QualityStatus

    var body: some View {
        switch status {
        case .running: ProgressView().controlSize(.small)
        case .pending: symbol("circle.dashed", .tertiary)
        case .failed: symbol("exclamationmark.triangle.fill", .orange)
        case .unavailable: symbol("minus.circle", .secondary)
        case .cancelled: symbol("xmark.circle", .secondary)
        case .measured, .notIncluded: EmptyView()
        }
    }

    private func symbol(_ name: String, _ style: some ShapeStyle) -> some View {
        Image(systemName: name).font(.footnote.weight(.semibold)).foregroundStyle(style).accessibilityHidden(true)
    }
}

extension QualityStatus {
    /// The words a row shows (and VoiceOver reads) in place of a value.
    var caption: String {
        switch self {
        case .pending: "等待中"
        // The header names the stage; rows only say a result is on its way.
        case .running: "检测中"
        case .measured: ""
        case .failed(let issue), .unavailable(let issue): issue.title
        case .cancelled: "已取消"
        case .notIncluded: "未包含"
        }
    }
    var issueDetail: String? {
        switch self { case .failed(let issue), .unavailable(let issue): issue.detail; default: nil }
    }
}

/// One line of the report. Before its result arrives it shows the step's status in the value's place,
/// so results fill in where the reader will later find them.
struct QualityRow<Value: View>: View {
    let title: String
    var subtitle: String?
    let status: QualityStatus
    @ViewBuilder var value: () -> Value
    @Environment(\.qualityIdle) private var idle
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes there is no room beside the title, so the value goes under it.
        let stacked = typeSize.isAccessibilitySize
        // A spinner has no text baseline, so status rows centre instead.
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: status == .measured ? .firstTextBaseline : .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Color.seekInk)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            .layoutPriority(1)
            if !stacked { Spacer(minLength: 8) }
            trailing.multilineTextAlignment(stacked ? .leading : .trailing)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var trailing: some View {
        if status == .measured {
            value()
        } else if idle, status == .pending {
            Text("—").foregroundStyle(.tertiary).accessibilityLabel("未开始")
        } else {
            HStack(spacing: 6) {
                Text(status.caption).font(.subheadline).foregroundStyle(.secondary)
                QualityStatusMark(status: status)
            }
        }
    }
}

extension QualityRow where Value == Text {
    init(_ title: String, subtitle: String? = nil, status: QualityStatus, value: String) {
        self.init(title: title, subtitle: subtitle, status: status) { Text(value).foregroundStyle(.secondary) }
    }
}

/// A large figure with its unit, such as "486 Mbps".
struct QualityFigure: View {
    let title: String
    let value: Double?
    let unit: String
    var format: (Double) -> String = QualityFormat.mbps
    var placeholder = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map(format) ?? placeholder)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(value == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.seekInk))
                    .contentTransition(.numericText(value: value ?? 0))
                    .lineLimit(1).minimumScaleFactor(0.6)
                if value != nil { Text(unit).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\(format($0)) \(unit)" } ?? "未测得")
    }
}

/// The thin overall progress line in the header card.
struct QualityProgressLine: View {
    let fraction: Double

    var body: some View {
        ProgressView(value: min(max(fraction, 0), 1))
            .progressViewStyle(.linear).tint(Color.seekInk)
            .animation(.easeOut(duration: 0.25), value: fraction)
            .accessibilityHidden(true)
    }
}

/// A coloured dot for verdict-like results. Small, so colour stays a hint rather than a block.
struct QualityDot: View {
    let tint: Color
    var body: some View { Circle().fill(tint).frame(width: 7, height: 7).accessibilityHidden(true) }
}

extension ReputationVerdict {
    var tint: Color {
        switch self { case .clean: .green; case .low: .green.opacity(0.6); case .medium: .orange; case .high: .red; case .unknown: .secondary }
    }
}

extension ServiceOutcome {
    var tint: Color {
        switch self { case .reachable: .green; case .regionRestricted: .orange; case .timedOut: .red; case .undetermined: .secondary }
    }
}

extension PortOutcome {
    var tint: Color {
        switch self { case .open: .green; case .refused, .timedOut: .orange; case .undetermined: .secondary }
    }
}

extension NetworkKind {
    var symbol: String {
        switch self { case .wifi: "wifi"; case .cellular: "antenna.radiowaves.left.and.right"; case .wired: "cable.connector"; case .other: "network"; case .offline: "wifi.slash" }
    }
}
