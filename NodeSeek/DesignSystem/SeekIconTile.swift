import SwiftUI

struct SeekIconTile: View {
    let symbol: ImageResource
    var tint: Color = .seekButtonIcon

    var body: some View {
        Image(symbol).font(.body.weight(.medium)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(tint).frame(width: 36, height: 36)
            .background(tint.opacity(0.08), in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}
