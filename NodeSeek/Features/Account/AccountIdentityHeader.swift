import NodeSeekCore
import SwiftUI

struct AccountIdentityHeader: View {
    let user: SignedInUser

    var body: some View {
        VStack(spacing: 12) {
            AvatarView(name: user.name, url: user.avatarURL, size: 80)
            Text(user.name).font(.title.bold()).foregroundStyle(Color.seekInk)
            HStack(spacing: 8) {
                Text("UID \(user.id.formatted(.number.grouping(.never)))")
                if let level = user.level { Text("Lv \(level)") }
            }
            .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.seekTray, in: .capsule)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(user.name)，查看个人主页")
    }
}
