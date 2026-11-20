import NodeSeekCore
import SwiftUI

struct AttendanceStatusCard: View {
    let board: AttendanceBoard
    let coins: Int?
    let signingMode: AttendanceSignInMode?
    let onSignIn: (AttendanceSignInMode) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var checkInDate: Date? {
        board.createdAt.flatMap(ForumDate.parse)
    }

    var body: some View {
        if let gain = board.gain {
            checkedInContent(gain: gain)
        } else {
            uncheckedContent
        }
    }

    private func checkedInContent(gain: Int) -> some View {
        VStack(alignment: .leading, spacing: AttendanceMetrics.blockSpacing) {
            VStack(alignment: .leading, spacing: AttendanceMetrics.textSpacing) {
                HStack(spacing: 6) {
                    Image(.inkAttended)
                        .foregroundStyle(Color.seekGreen)
                        .accessibilityHidden(true)
                    Text("今日已签到")
                        .foregroundStyle(Color.seekGreen)
                    if let checkInDate {
                        Text("·")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(checkInDate, format: .dateTime.hour().minute())
                            .fontWeight(.regular)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(.semibold))

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(gain > 0 ? "+\(gain)" : gain.formatted())
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.seekInk)
                    Text("个鸡腿")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            if board.order != nil || coins != nil {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: AttendanceMetrics.pillSpacing))
                    : AnyLayout(HStackLayout(spacing: AttendanceMetrics.pillSpacing))
                layout {
                    if let order = board.order {
                        AttendanceStatPill(text: "今日第 \(order.formatted()) 位")
                    }
                    if let coins {
                        AttendanceStatPill(text: "当前 \(coins.formatted()) 鸡腿")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("attendance-status-card")
    }

    private var uncheckedContent: some View {
        VStack(alignment: .leading, spacing: AttendanceMetrics.blockSpacing) {
            VStack(alignment: .leading, spacing: AttendanceMetrics.textSpacing) {
                Text("今日尚未签到")
                    .font(.title3.bold())
                    .foregroundStyle(Color.seekInk)
                Text("固定领取 5 个鸡腿，或试试手气抽取随机奖励。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if typeSize.isAccessibilitySize {
                stackedButtons
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AttendanceMetrics.buttonSpacing) {
                        signInButton(mode: .fixed, singleLine: true)
                        signInButton(mode: .random, singleLine: true)
                    }
                    stackedButtons
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stackedButtons: some View {
        VStack(spacing: AttendanceMetrics.buttonSpacing) {
            signInButton(mode: .fixed, singleLine: false)
            signInButton(mode: .random, singleLine: false)
        }
    }

    @ViewBuilder
    private func signInButton(mode: AttendanceSignInMode, singleLine: Bool) -> some View {
        let isPrimary = mode == .fixed
        let isActive = signingMode == mode
        let isOtherActive = signingMode != nil && signingMode != mode
        Button {
            onSignIn(mode)
        } label: {
            ZStack {
                HStack(spacing: 6) {
                    Image(isPrimary ? .inkClaimReward : .inkRandomReward)
                        .accessibilityHidden(true)
                    Text(isPrimary ? "领取 5 鸡腿" : "试试手气")
                        .lineLimit(singleLine ? 1 : nil)
                }
                .fixedSize(horizontal: singleLine, vertical: false)
                .opacity(isActive ? 0 : 1)
                if isActive {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(isPrimary ? Color.seekOnInk : Color.seekInk)
                        Text("正在签到…")
                            .lineLimit(1)
                    }
                }
            }
            .clipShape(.rect)
        }
        .buttonStyle(.seekPill(primary: isPrimary, surface: .seekTray))
        .allowsHitTesting(signingMode == nil)
        .disabled(isOtherActive)
        .accessibilityIdentifier(isPrimary ? "attendance-fixed-button" : "attendance-random-button")
        .accessibilityLabel(
            isActive
                ? "正在签到"
                : (isPrimary ? "签到，领取 5 个鸡腿" : "试试手气，领取随机奖励")
        )
    }
}

private struct AttendanceStatPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, AttendanceMetrics.pillHorizontalPadding)
            .padding(.vertical, AttendanceMetrics.pillVerticalPadding)
            .background(Color.seekTray, in: .capsule)
    }
}
