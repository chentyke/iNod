import NodeSeekCore
import SwiftUI

struct StardustRecordRow: View {
    let record: StardustRecord
    let onFilterPeer: (Int) -> Void
    let onFilterReference: (Int) -> Void
    @Environment(\.openMemberDestination) private var openMember
    @Environment(\.dynamicTypeSize) private var typeSize

    private var symbol: ImageResource {
        switch record.type {
        case "transfer":
            if record.diff > 0 { return .inkReceivedDust }
            if record.diff < 0 { return .inkSentDust }
            return .inkExchangeDust
        case "upvote":
            return .inkVoteIncome
        case "buyCode":
            return .inkBoughtInvite
        case "admin":
            return .inkAdminAdjustment
        default:
            return .inkStardust
        }
    }

    private var amountColor: Color {
        record.diff > 0 ? .seekGreen : .seekInk
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: StardustMetrics.rowSpacing) {
                        SeekIconTile(symbol: symbol)
                        Text(record.typeTitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.seekInk)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        amountLabel
                        balanceLabel
                    }
                    timestampRow
                    if record.validPeerID != nil {
                        peerAndReferenceRow
                    }
                }
            } else {
                HStack(alignment: .top, spacing: StardustMetrics.rowSpacing) {
                    SeekIconTile(symbol: symbol)
                    VStack(alignment: .leading, spacing: StardustMetrics.rowLineSpacing) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(record.typeTitle)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.seekInk)
                            Spacer(minLength: 8)
                            amountLabel
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            timestampRow
                            Spacer(minLength: 8)
                            balanceLabel
                        }
                        if record.validPeerID != nil {
                            peerAndReferenceRow
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
        .frame(minHeight: StardustMetrics.iconSize)
        .contentShape(.rect)
        .contextMenu {
            if let peerID = record.validPeerID {
                Button("查看对方主页", image: .inkProfile) {
                    openMember(.profile(peerID))
                }
                Button("筛选此用户记录", image: .inkFilterMember) {
                    onFilterPeer(peerID)
                }
            }
            if let refID = record.validRefID {
                Button("按此 Ref ID 筛选", image: .inkFilterReference) {
                    onFilterReference(refID)
                }
            }
        }
    }

    private var amountLabel: some View {
        Text(record.formattedDiff)
            .font(.body.weight(.semibold).monospacedDigit())
            .foregroundStyle(amountColor)
            .fixedSize()
    }

    private var balanceLabel: some View {
        Text("余额 \(record.result.formatted())")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var timestampRow: some View {
        HStack(spacing: 6) {
            ForumDateText(value: record.created_at)
            if record.validPeerID == nil, let refID = record.validRefID {
                Text("·")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("Ref ID \(String(refID))")
            }
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var peerAndReferenceRow: some View {
        if let peerID = record.validPeerID {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Button {
                    openMember(.profile(peerID))
                } label: {
                    HStack(spacing: 4) {
                        Image(.inkProfile)
                            .foregroundStyle(Color.seekButtonIcon)
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text("对方 UID \(String(peerID))")
                            .monospacedDigit()
                        Image(.inkNext)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.seekButtonIcon)
                            .accessibilityHidden(true)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.seekInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.seekTray, in: .capsule)
                    .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.seekRow)
                .accessibilityIdentifier("stardust-peer-\(record.id)")
                .accessibilityLabel("对方 UID \(String(peerID))，查看个人主页")

                if let refID = record.validRefID {
                    Text("Ref ID \(String(refID))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
