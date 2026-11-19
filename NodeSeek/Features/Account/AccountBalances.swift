import NodeSeekCore
import SwiftUI

enum AccountBalanceMetrics {
    static let cardPadding: CGFloat = 16
    static let tileSpacing: CGFloat = 12
    static let stackedTileSpacing: CGFloat = 10
    static let tileCornerRadius: CGFloat = 16
    static let tileHorizontalPadding: CGFloat = 14
    /// Trims font line-height air above the label and descender space below the rounded digits.
    static let tileTopGlyphTrim: CGFloat = 1
    static let tileBottomGlyphTrim: CGFloat = 6
    static let tileValueSpacing: CGFloat = 8
    static let tileHeaderIconSpacing: CGFloat = 6

    static let rowSpacing: CGFloat = 12
    static let rowVerticalInset: CGFloat = 10
    static let iconTileSize: CGFloat = 36
    static let separatorLeading: CGFloat = iconTileSize + rowSpacing
    static let balancesBottomInset: CGFloat = cardPadding - rowVerticalInset

    static let tileInsets = EdgeInsets(
        top: tileHorizontalPadding - tileTopGlyphTrim,
        leading: tileHorizontalPadding,
        bottom: tileHorizontalPadding - tileBottomGlyphTrim,
        trailing: tileHorizontalPadding
    )

    static let balancesRowInsets = EdgeInsets(
        top: cardPadding,
        leading: cardPadding,
        bottom: balancesBottomInset,
        trailing: cardPadding
    )

    static let middleRowInsets = EdgeInsets(
        top: rowVerticalInset,
        leading: cardPadding,
        bottom: rowVerticalInset,
        trailing: cardPadding
    )

    static let lastRowInsets = EdgeInsets(
        top: rowVerticalInset,
        leading: cardPadding,
        bottom: cardPadding,
        trailing: cardPadding
    )
}

struct AccountBalances: View {
    let user: SignedInUser
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openAccountDestination) private var navigate

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: AccountBalanceMetrics.stackedTileSpacing))
            : AnyLayout(HStackLayout(spacing: AccountBalanceMetrics.tileSpacing))
        layout {
            Button {
                navigate(.ledger(.chicken))
            } label: {
                SeekBalanceValue(title: "鸡腿", symbol: .inkDrumstick, value: user.coins, tint: .orange)
            }
            .buttonStyle(.seekCard)
            .accessibilityIdentifier("account-balance-chicken")
            .accessibilityHint("查看鸡腿明细")

            Button {
                navigate(.stardustHistory)
            } label: {
                SeekBalanceValue(title: "星尘", symbol: .inkStardust, value: user.stardust, tint: .indigo)
            }
            .buttonStyle(.seekCard)
            .accessibilityIdentifier("account-balance-stardust")
            .accessibilityHint("查看星尘明细与转账")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-balances-grid")
    }
}

struct AccountBalanceNavigationRow: View {
    let title: String
    let symbol: ImageResource
    var progress: AccountLevel.Progress?
    let destination: AccountDestination
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationLink(value: destination) {
            rowContent
                .frame(minHeight: AccountBalanceMetrics.iconTileSize)
                .modifier(AccountRowAccessibilityValueModifier(title: title, value: progress?.accessibilitySummary))
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        if let progress, typeSize.isAccessibilitySize {
            HStack(spacing: AccountBalanceMetrics.rowSpacing) {
                SeekIconTile(symbol: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.seekInk)
                    progressStatusLabel(progress)
                }
            }
        } else {
            HStack(spacing: AccountBalanceMetrics.rowSpacing) {
                SeekIconTile(symbol: symbol)
                Text(title)
                    .foregroundStyle(Color.seekInk)
                if let progress {
                    Spacer(minLength: 8)
                    progressStatusLabel(progress)
                }
            }
        }
    }

    private func progressStatusLabel(_ progress: AccountLevel.Progress) -> some View {
        HStack(spacing: 4) {
            if progress.isMaxLevel {
                Image(.inkLevelBadge)
                    .font(.caption)
                    .foregroundStyle(Color.seekGreen)
                    .accessibilityHidden(true)
            }
            Text(progress.compactSummary)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct AccountRowAccessibilityValueModifier: ViewModifier {
    let title: String
    let value: String?

    func body(content: Content) -> some View {
        if let value {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(value)
        } else {
            content
        }
    }
}
