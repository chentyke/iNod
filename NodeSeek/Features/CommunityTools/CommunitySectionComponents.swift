import SwiftUI
import UIKit

enum CommunityMetrics {
    static let cardPadding: CGFloat = 16
    static let tileSpacing: CGFloat = 12
    static let stackedTileSpacing: CGFloat = 10
    static let tileCornerRadius: CGFloat = 16
    static let tilePadding: CGFloat = 14
    /// Trims descender air under the footnote subtitle so visual top and bottom margins inside the tile match.
    static let tileBottomGlyphTrim: CGFloat = 2

    static let rowVerticalInset: CGFloat = 10
    static let rowHorizontalInset: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let rowLineSpacing: CGFloat = 3
    static let iconSize: CGFloat = 36
    static let avatarSize: CGFloat = 44
    static let separatorInset: CGFloat = iconSize + rowSpacing
    static let avatarSeparatorInset: CGFloat = avatarSize + rowSpacing

    static let tileInsets = EdgeInsets(
        top: tilePadding,
        leading: tilePadding,
        bottom: tilePadding - tileBottomGlyphTrim,
        trailing: tilePadding
    )

    static let tilesRowInsets = EdgeInsets(
        top: cardPadding,
        leading: cardPadding,
        bottom: cardPadding - rowVerticalInset,
        trailing: cardPadding
    )

    static let rowInsets = EdgeInsets(
        top: rowVerticalInset,
        leading: rowHorizontalInset,
        bottom: rowVerticalInset,
        trailing: rowHorizontalInset
    )

    static let lastCommunityRowInsets = EdgeInsets(
        top: rowVerticalInset,
        leading: rowHorizontalInset,
        bottom: cardPadding - tileBottomGlyphTrim,
        trailing: rowHorizontalInset
    )

    static let searchRowInsets = EdgeInsets(
        top: 8,
        leading: 14,
        bottom: 8,
        trailing: 10
    )

    static let filterBannerInsets = EdgeInsets(
        top: 9,
        leading: rowHorizontalInset,
        bottom: 9,
        trailing: rowHorizontalInset
    )
}

struct CommunityFeatureTile: View {
    let title: String
    let subtitle: String
    let symbol: ImageResource
    var tint: Color = .seekInk

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.10), in: .rect(cornerRadius: 9))
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                Image(.inkNext)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.seekInk)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(CommunityMetrics.tileInsets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.seekTray, in: .rect(cornerRadius: CommunityMetrics.tileCornerRadius))
        .contentShape(.rect(cornerRadius: CommunityMetrics.tileCornerRadius))
    }
}

struct CommunitySearchFieldRow: View {
    let searchIcon: ImageResource
    let prompt: String
    @Binding var text: String
    var identifier: String
    var submitButtonIdentifier: String?
    let onSubmit: () -> Void
    let onClear: () -> Void
    @FocusState private var isFocused: Bool

    private var hasInput: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func triggerSubmit() {
        isFocused = false
        onSubmit()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(searchIcon)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(triggerSubmit)
                .frame(minHeight: 36)
                .accessibilityIdentifier(identifier)

            if !text.isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(.inkClearInput)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除输入")
                .accessibilityIdentifier("\(identifier)-clear")
            }

            if hasInput {
                Button(action: triggerSubmit) {
                    Text("查找")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.seekOnInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Color.seekInk, in: .capsule)
                }
                .buttonStyle(.seekRow)
                .accessibilityIdentifier(submitButtonIdentifier ?? "\(identifier)-submit")
            }
        }
    }
}

struct CommunityActiveFilterRow: View {
    let label: String
    var identifier: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(.inkFilter)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.seekGreen)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.seekInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.seekTray, in: .capsule)

            Spacer(minLength: 8)

            Button("清除", action: onClear)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.seekRow)
                .accessibilityIdentifier("\(identifier)-clear")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

struct CommunityCopyCapsule: View {
    let value: String
    var title: String = "复制"
    var copiedTitle: String = "已复制"
    var accessibilityLabelText: String
    var identifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            resetTask?.cancel()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                copied = true
            }
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                    copied = false
                }
            }
        } label: {
            ZStack {
                Text(title)
                    .opacity(copied ? 0 : 1)
                HStack(spacing: 4) {
                    Image(.inkCheck)
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                    Text(copiedTitle)
                }
                .foregroundStyle(Color.seekGreen)
                .opacity(copied ? 1 : 0)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.seekInk)
            .padding(.horizontal, 12)
            .frame(minWidth: 68, minHeight: 34)
            .background(Color.seekTray, in: .capsule)
            .clipShape(.capsule)
        }
        .buttonStyle(.seekRow)
        .onDisappear { resetTask?.cancel() }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(copied ? "\(accessibilityLabelText)，已复制" : accessibilityLabelText)
    }
}

extension View {
    func communityRowStyle(alignSeparator: Bool = true, separatorInset: CGFloat = CommunityMetrics.separatorInset) -> some View {
        self
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                alignSeparator ? dimensions[.leading] + separatorInset : dimensions[.leading]
            }
            .listRowInsets(CommunityMetrics.rowInsets)
            .listRowBackground(Color.seekCard)
    }
}
