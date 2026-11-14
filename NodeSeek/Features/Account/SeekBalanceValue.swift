import SwiftUI

struct SeekBalanceValue: View {
    let title: String
    let symbol: String
    let value: Int?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(tint)
            Text(value.map { $0.formatted() } ?? "—")
                .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(Color.seekInk)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(.horizontal, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
