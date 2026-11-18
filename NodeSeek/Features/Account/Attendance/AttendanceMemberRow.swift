import NodeSeekCore
import SwiftUI

struct AttendanceMemberRow: View {
    let member: AttendanceMember
    let isCurrentUser: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var avatarURL: URL {
        NodeSeekRoute.origin.appending(path: "avatar/\(member.id).png")
    }

    private var rewardText: String {
        member.gain > 0 ? "+\(member.gain)" : member.gain.formatted()
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: AttendanceMetrics.rowSpacing) {
                        rankBadge
                        AvatarView(name: member.name, url: avatarURL, size: AttendanceMetrics.avatarSize)
                        nameLabel
                    }
                    rewardLabel
                }
            } else {
                HStack(spacing: AttendanceMetrics.rowSpacing) {
                    rankBadge
                    AvatarView(name: member.name, url: avatarURL, size: AttendanceMetrics.avatarSize)
                    nameLabel
                    Spacer(minLength: 8)
                    rewardLabel
                }
            }
        }
        .frame(minHeight: AttendanceMetrics.avatarSize)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var rankBadge: some View {
        Group {
            if member.rank <= 3 {
                Text(member.rank.formatted())
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.seekInk)
                    .frame(width: AttendanceMetrics.podiumBadgeSize, height: AttendanceMetrics.podiumBadgeSize)
                    .background(Color.seekTray, in: .circle)
            } else {
                Text(member.rank.formatted())
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: AttendanceMetrics.rankWidth)
        .accessibilityLabel("第 \(member.rank) 位")
    }

    private var nameLabel: some View {
        HStack(spacing: 6) {
            Text(member.name)
                .font(isCurrentUser ? .body.weight(.semibold) : .body)
                .foregroundStyle(Color.seekInk)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            if isCurrentUser {
                Text("我")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.seekGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.seekGreen.opacity(0.08), in: .capsule)
                    .fixedSize()
            }
        }
    }

    private var rewardLabel: some View {
        Text(rewardText)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(member.gain > 0 ? Color.seekGreen : .secondary)
            .fixedSize()
            .accessibilityLabel("获得 \(member.gain) 个鸡腿")
    }
}
