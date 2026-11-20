import NodeSeekCore
import SwiftUI

struct AccountLevelCard: View {
    let progress: AccountLevel.Progress?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ProgressMetrics.blockSpacing) {
            VStack(alignment: .leading, spacing: ProgressMetrics.textSpacing) {
                eyebrow
                Text(progress.map { "Lv \($0.level)" } ?? "Lv —")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.seekInk)
            }

            if let progress {
                if let nextLevel = progress.nextLevel, let remaining = progress.remainingCoins {
                    VStack(alignment: .leading, spacing: ProgressMetrics.progressSpacing) {
                        ProgressView(value: progress.fraction)
                            .progressViewStyle(.linear)
                            .tint(Color.seekGreen)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress.fraction)
                            .accessibilityHidden(true)
                        Text("距离 Lv \(nextLevel) 还需 \(remaining.formatted()) 个鸡腿")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("已解锁全部社区等级阅读权限。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                let pillLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: ProgressMetrics.pillSpacing))
                    : AnyLayout(HStackLayout(spacing: ProgressMetrics.pillSpacing))
                pillLayout {
                    ProgressStatPill(text: "当前 \(progress.coins.formatted()) 鸡腿")
                    if let nextLevel = progress.nextLevel, let nextTarget = progress.nextTarget {
                        ProgressStatPill(text: "Lv \(nextLevel) 门槛 \(nextTarget.formatted()) 鸡腿")
                    } else {
                        ProgressStatPill(text: "满级门槛 \(progress.currentFloor.formatted()) 鸡腿")
                    }
                }
            } else {
                Text("下拉刷新以同步当前鸡腿余额与等级。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress-level-card")
    }

    @ViewBuilder
    private var eyebrow: some View {
        if progress?.isMaxLevel == true {
            HStack(spacing: 6) {
                Image(.inkLevelBadge)
                    .foregroundStyle(Color.seekGreen)
                    .accessibilityHidden(true)
                Text("已达最高等级")
                    .foregroundStyle(Color.seekGreen)
            }
            .font(.subheadline.weight(.semibold))
        } else {
            Text("社区等级")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProgressStatPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, ProgressMetrics.pillHorizontalPadding)
            .padding(.vertical, ProgressMetrics.pillVerticalPadding)
            .background(Color.seekTray, in: .capsule)
    }
}
