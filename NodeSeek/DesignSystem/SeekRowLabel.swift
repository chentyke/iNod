import SwiftUI

struct SeekRowLabel: View {
    let title: String
    let symbol: ImageResource
    /// Marks a row that leaves the app, in place of the chevron a navigation row gets.
    var opensExternally = false

    var body: some View {
        HStack(spacing: 12) {
            SeekIconTile(symbol: symbol)
            Text(title).foregroundStyle(Color.seekInk)
            if opensExternally {
                Spacer(minLength: 0)
                Image(.inkOpenExternal)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.seekButtonIcon)
                    .accessibilityHidden(true)
            }
        }.frame(minHeight: 44)
    }
}
