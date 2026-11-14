import NodeSeekCore
import SwiftUI

struct ProfileIdentityHeader: View {
    let profile: AccountProfile

    var body: some View {
        VStack(spacing: 12) {
            AvatarView(name: profile.name, url: profile.recipient.avatarURL, size: 80)
            Text(profile.name).font(.title.bold()).foregroundStyle(Color.seekInk)
            HStack(spacing: 10) {
                Text("UID \(profile.id.formatted(.number.grouping(.never)))")
                    .textSelection(.enabled)
                if let level = profile.level {
                    Text("Lv \(level)")
                        .accessibilityLabel("等级 \(level)")
                }
            }
            .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 7).background(Color.seekTray, in: .capsule)
            if let bio = profile.bio, !bio.isEmpty { Text(bio).font(.subheadline).multilineTextAlignment(.center) }
            if let date = profile.createdAt {
                HStack(spacing: 5) { Text("加入于"); ForumDateText(value: date) }.font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}
