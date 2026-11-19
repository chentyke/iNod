import SwiftUI

struct AccountNavigationRow: View {
    let title: String
    let symbol: ImageResource
    var count: Int?
    let destination: AccountDestination
    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                SeekIconTile(symbol: symbol)
                Text(title).foregroundStyle(Color.seekInk)
                Spacer()
                if let count { Text(count.formatted()).monospacedDigit().foregroundStyle(.secondary) }
            }.frame(minHeight: 44)
        }
    }
}
