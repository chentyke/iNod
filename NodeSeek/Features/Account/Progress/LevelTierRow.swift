import NodeSeekCore
import SwiftUI

struct LevelTierRow: View {
    let tier: AccountLevel.Tier
    let currentLevel: Int?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isCurrent: Bool {
        currentLevel == tier.level
    }

    private var isReached: Bool {
        guard let currentLevel else { return false }
        return tier.level <= currentLevel
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: ProgressMetrics.rowSpacing) {
                        tierBadge
                        titleLabel
                    }
                    thresholdLabel
                }
            } else {
                HStack(spacing: ProgressMetrics.rowSpacing) {
                    tierBadge
                    titleLabel
                    Spacer(minLength: 8)
                    thresholdLabel
                }
            }
        }
        .frame(minHeight: ProgressMetrics.tierBadgeSize)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress-tier-\(tier.level)")
    }

    private var tierBadge: some View {
        Group {
            if isCurrent {
                Image(.inkCurrentLevel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.seekGreen)
                    .frame(width: ProgressMetrics.tierBadgeSize, height: ProgressMetrics.tierBadgeSize)
                    .background(Color.seekGreen.opacity(0.08), in: .circle)
            } else if isReached {
                Image(.inkLevelReached)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: ProgressMetrics.tierBadgeSize, height: ProgressMetrics.tierBadgeSize)
                    .background(Color.seekTray, in: .circle)
            } else {
                Text(tier.level.formatted())
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: ProgressMetrics.tierBadgeSize, height: ProgressMetrics.tierBadgeSize)
                    .background(Color.seekTray, in: .circle)
            }
        }
        .accessibilityHidden(true)
    }

    private var titleLabel: some View {
        HStack(spacing: 6) {
            Text("Lv \(tier.level)")
                .font(isCurrent ? .body.weight(.semibold) : .body)
                .monospacedDigit()
                .foregroundStyle(isReached ? Color.seekInk : .secondary)
            if isCurrent {
                Text("当前")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.seekGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.seekGreen.opacity(0.08), in: .capsule)
                    .fixedSize()
            }
        }
    }

    private var thresholdLabel: some View {
        Text("\(tier.requiredCoins.formatted()) 鸡腿")
            .font(isCurrent ? .subheadline.weight(.semibold).monospacedDigit() : .subheadline.monospacedDigit())
            .foregroundStyle(isCurrent ? Color.seekInk : .secondary)
            .fixedSize()
    }
}
