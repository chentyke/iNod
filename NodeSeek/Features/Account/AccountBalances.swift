import NodeSeekCore
import SwiftUI

struct AccountBalances: View {
    let user: SignedInUser
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openAccountDestination) private var navigate

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            Button { navigate(.ledger(.chicken)) } label: {
                SeekBalanceValue(title: "鸡腿", symbol: "fork.knife", value: user.coins, tint: .orange)
            }
            if typeSize.isAccessibilitySize { Divider() } else { Divider().frame(height: 46) }
            Button { navigate(.stardustHistory) } label: {
                SeekBalanceValue(title: "星尘", symbol: "sparkles", value: user.stardust, tint: .indigo)
            }
        }
        .buttonStyle(.seekRow)
        .padding(18)
    }
}
