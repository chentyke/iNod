import NodeSeekCore
import SwiftUI

enum DailyProgressItemKind: Equatable {
    case postBonus
    case commentBonus
    case freeLike

    var title: String {
        switch self {
        case .postBonus: "发帖奖励"
        case .commentBonus: "回复奖励"
        case .freeLike: "免费鸡腿"
        }
    }

    var symbol: String {
        switch self {
        case .postBonus: "text.bubble"
        case .commentBonus: "bubble.left"
        case .freeLike: "fork.knife"
        }
    }

    var identifier: String {
        switch self {
        case .postBonus: "progress-row-post"
        case .commentBonus: "progress-row-comment"
        case .freeLike: "progress-row-freelike"
        }
    }

    var isBonus: Bool {
        self != .freeLike
    }

    func subtitle(for quota: DailyProgress.Quota) -> String {
        switch self {
        case .postBonus:
            if quota.limit == 0 { return "今日暂无发帖奖励额度" }
            if quota.isReached { return "今日发帖奖励已领满" }
            return "还可获得 \(quota.remaining.formatted()) 次发帖奖励"
        case .commentBonus:
            if quota.limit == 0 { return "今日暂无回复奖励额度" }
            if quota.isReached { return "今日回复奖励已领满" }
            return "还可获得 \(quota.remaining.formatted()) 次回复奖励"
        case .freeLike:
            if quota.limit == 0 { return "当前暂无每日免费投喂额度" }
            if quota.isReached { return "今日免费投喂额度已用完" }
            return "还可免费投喂 \(quota.remaining.formatted()) 次"
        }
    }
}

struct DailyProgressRow: View {
    let kind: DailyProgressItemKind
    let quota: DailyProgress.Quota
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsEarnedHighlight: Bool {
        kind.isBonus && quota.isReached
    }

    private var isMuted: Bool {
        quota.limit == 0 || (kind == .freeLike && quota.isReached)
    }

    var body: some View {
        HStack(alignment: .top, spacing: ProgressMetrics.rowSpacing) {
            SeekIconTile(symbol: kind.symbol)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: ProgressMetrics.progressSpacing) {
                let headerLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                headerLayout {
                    Text(kind.title)
                        .font(.body)
                        .foregroundStyle(Color.seekInk)
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: 8)
                    }
                    countBadge
                }

                ProgressView(value: quota.fraction)
                    .progressViewStyle(.linear)
                    .tint(isMuted ? .secondary : Color.seekGreen)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: quota.fraction)
                    .accessibilityHidden(true)

                Text(kind.subtitle(for: quota))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(kind.identifier)
    }

    private var countBadge: some View {
        HStack(spacing: 4) {
            if showsEarnedHighlight {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.seekGreen)
                    .accessibilityHidden(true)
            }
            Text("\(quota.used.formatted()) / \(quota.limit.formatted())")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(
                    showsEarnedHighlight
                        ? AnyShapeStyle(Color.seekGreen)
                        : (isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.seekInk))
                )
        }
        .fixedSize()
    }
}
