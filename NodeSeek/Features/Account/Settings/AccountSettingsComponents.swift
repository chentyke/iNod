import NodeSeekCore
import NodeSeekClient
import SwiftUI

enum AccountSettingsMetrics {
    static let cardPadding: CGFloat = 20
    static let compactCardPadding: CGFloat = 16
    /// Trims font line-height air above the first text line and below the last text line so visual top and bottom gaps match.
    static let topGlyphTrim: CGFloat = 3
    static let bottomGlyphTrim: CGFloat = 3

    static let blockSpacing: CGFloat = 16
    static let textSpacing: CGFloat = 6
    static let buttonSpacing: CGFloat = 10
    static let pillHorizontalPadding: CGFloat = 10
    static let pillVerticalPadding: CGFloat = 4

    static let rowVerticalInset: CGFloat = 10
    static let rowHorizontalInset: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let rowLineSpacing: CGFloat = 3
    static let iconSize: CGFloat = 36
    static let accountAvatarSize: CGFloat = 48
    static let editorAvatarSize: CGFloat = 104
    static let separatorInset: CGFloat = iconSize + rowSpacing

    static let rowInsets = EdgeInsets(
        top: rowVerticalInset,
        leading: rowHorizontalInset,
        bottom: rowVerticalInset,
        trailing: rowHorizontalInset
    )

    static let accountCardInsets = EdgeInsets(
        top: compactCardPadding,
        leading: compactCardPadding,
        bottom: compactCardPadding,
        trailing: compactCardPadding
    )

    static let shapeCardInsets = EdgeInsets(
        top: cardPadding,
        leading: cardPadding,
        bottom: cardPadding,
        trailing: cardPadding
    )

    static func cardInsets(hasBottomCapsule: Bool) -> EdgeInsets {
        EdgeInsets(
            top: cardPadding - topGlyphTrim,
            leading: cardPadding,
            bottom: hasBottomCapsule ? cardPadding : cardPadding - bottomGlyphTrim,
            trailing: cardPadding
        )
    }
}

struct SettingsStatusPill: View {
    let text: String
    var active = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? Color.seekGreen : .secondary)
            .padding(.horizontal, AccountSettingsMetrics.pillHorizontalPadding)
            .padding(.vertical, AccountSettingsMetrics.pillVerticalPadding)
            .background(active ? Color.seekGreen.opacity(0.08) : Color.seekTray, in: .capsule)
            .fixedSize()
    }
}

struct SettingsRowContent: View {
    let title: String
    var subtitle: String?
    let symbol: ImageResource
    var tint: Color = .seekInk
    var badge: (text: String, active: Bool)?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize, let badge {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                        SeekIconTile(symbol: symbol, tint: tint)
                        labelStack
                    }
                    SettingsStatusPill(text: badge.text, active: badge.active)
                }
            } else {
                HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                    SeekIconTile(symbol: symbol, tint: tint)
                    labelStack
                    if let badge {
                        Spacer(minLength: 8)
                        SettingsStatusPill(text: badge.text, active: badge.active)
                    }
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var labelStack: some View {
        VStack(alignment: .leading, spacing: AccountSettingsMetrics.rowLineSpacing) {
            Text(title)
                .foregroundStyle(Color.seekInk)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A capsule action button whose busy spinner renders inside the fixed capsule bounds,
/// keeping surrounding card and list heights constant during async transitions.
struct SettingsActionPill: View {
    let title: String
    var symbol: ImageResource?
    var busyTitle: String = "处理中…"
    var isBusy = false
    var primary = true
    var destructive = false
    var fullWidth = true
    var surface: Color = .seekTray
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    private var labelStyle: AnyShapeStyle? {
        guard isEnabled, destructive else { return nil }
        return AnyShapeStyle(Color.red)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 6) {
                    if let symbol {
                        Image(symbol)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .lineLimit(1)
                }
                .opacity(isBusy ? 0 : 1)

                if isBusy {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(destructive ? .red : (primary ? Color.seekOnInk : Color.seekInk))
                        Text(busyTitle)
                            .lineLimit(1)
                    }
                }
            }
            .modifier(OptionalForegroundModifier(style: labelStyle))
            .clipShape(.rect)
        }
        .buttonStyle(.seekPill(primary: primary && !destructive, fullWidth: fullWidth, surface: surface))
        .allowsHitTesting(!isBusy)
    }
}

private struct OptionalForegroundModifier: ViewModifier {
    let style: AnyShapeStyle?

    func body(content: Content) -> some View {
        if let style {
            content.foregroundStyle(style)
        } else {
            content
        }
    }
}

struct SettingsFeedbackRow: View {
    let message: String
    var isSuccess = true

    var body: some View {
        HStack(spacing: 10) {
            Image(isSuccess ? .inkFeedbackOK : .inkFeedbackError)
                .foregroundStyle(isSuccess ? Color.seekGreen : .red)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(isSuccess ? Color.seekInk : .red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func settingsRowStyle(alignSeparator: Bool = true) -> some View {
        self
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                alignSeparator ? dimensions[.leading] + AccountSettingsMetrics.separatorInset : dimensions[.leading]
            }
            .listRowInsets(AccountSettingsMetrics.rowInsets)
            .listRowBackground(Color.seekCard)
    }
}
