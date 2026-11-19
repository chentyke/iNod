import SwiftUI

struct PostPinLabel: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(.inkPinnedPost).imageScale(.small).accessibilityHidden(true)
            Text("置顶")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.seekGreen)
        .fixedSize()
    }
}
