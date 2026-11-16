import SwiftUI

struct SeekRowLabel: View {
    let title: String
    let symbol: String
    /// Marks a row that leaves the app, in place of the chevron a navigation row gets.
    var opensExternally = false

    var body: some View {
        HStack(spacing: 12) {
            SeekIconTile(symbol: symbol)
            Text(title).foregroundStyle(Color.seekInk)
            if opensExternally {
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    // A literal colour, because `.tertiary` inside a button picks up the green tint.
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
        }.frame(minHeight: 44)
    }
}
