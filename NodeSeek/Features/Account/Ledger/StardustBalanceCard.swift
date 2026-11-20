import SwiftUI

struct StardustBalanceCard: View {
    let stardust: Int?
    let onTransfer: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var balanceText: String {
        stardust.map { $0.formatted() } ?? "—"
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StardustMetrics.cardSpacing) {
                    balanceSummary
                    transferButton(fullWidth: true)
                }
            } else {
                HStack(alignment: .center, spacing: StardustMetrics.cardSpacing) {
                    balanceSummary
                    Spacer(minLength: 12)
                    transferButton(fullWidth: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stardust-balance-card")
    }

    private var balanceSummary: some View {
        VStack(alignment: .leading, spacing: StardustMetrics.balanceLabelSpacing) {
            HStack(spacing: 6) {
                Image(.inkStardust)
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)
                Text("当前星尘")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))

            Text(balanceText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.seekInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stardust-balance-summary")
    }

    private func transferButton(fullWidth: Bool) -> some View {
        Button(action: onTransfer) {
            HStack(spacing: 6) {
                Image(.inkTransferDust)
                    .foregroundStyle(Color.seekButtonIconOnFill)
                    .accessibilityHidden(true)
                Text("转账")
                    .lineLimit(1)
            }
        }
        .buttonStyle(.seekPill(primary: true, fullWidth: fullWidth))
        .accessibilityIdentifier("stardust-transfer-button")
        .accessibilityLabel("星尘转账")
    }
}
