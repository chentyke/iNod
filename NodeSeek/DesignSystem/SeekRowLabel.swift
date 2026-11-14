import SwiftUI

struct SeekRowLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            SeekIconTile(symbol: symbol)
            Text(title).foregroundStyle(Color.seekInk)
        }.frame(minHeight: 44)
    }
}
