import SwiftUI

struct SeekPillLabel: View {
    let title: String
    let symbol: ImageResource
    var primary = true
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(symbol)
                .foregroundStyle(primary && isEnabled ? Color.seekButtonIconOnFill : .seekButtonIcon)
        }
    }
}
