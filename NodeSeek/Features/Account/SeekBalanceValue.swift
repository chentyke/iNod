import SwiftUI

struct SeekBalanceValue: View {
    let title: String
    let symbol: String
    let value: Int?
    let tint: Color

    private var formattedValue: String {
        value.map { $0.formatted() } ?? "—"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AccountBalanceMetrics.tileCornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: AccountBalanceMetrics.tileValueSpacing) {
            HStack(spacing: AccountBalanceMetrics.tileHeaderIconSpacing) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    // Literal colour so `.tertiary` inside a button doesn't inherit accent tint.
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            Text(formattedValue)
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(value == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.seekInk))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AccountBalanceMetrics.tileInsets)
        .background(Color.seekTray, in: shape)
        .contentShape(shape)
        .contentShape(.hoverEffect, shape)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { $0.formatted() } ?? "未知")
    }
}
