import SwiftUI

struct PostRankLabel: View {
    let rank: Int

    static func title(for rank: Int) -> String {
        rank == 255 ? "仅作者可见" : "Lv \(rank) 可见"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(.inkReadPermission).imageScale(.small).accessibilityHidden(true)
            Text(Self.title(for: rank))
        }
        .foregroundStyle(.secondary)
    }
}
