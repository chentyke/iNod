import NodeSeekCore
import SwiftUI

struct LedgerRow: View {
    let entry: LedgerEntry
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.reason).font(.body)
                ForumDateText(value: entry.createdAt).font(.caption).foregroundStyle(.secondary)
                if let peer = entry.peerID, peer > 0 { Text("对方 UID \(peer)").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 7) {
                Text(entry.change > 0 ? "+\(entry.change)" : entry.change.formatted())
                    .font(.headline.monospacedDigit()).foregroundStyle(entry.change > 0 ? Color.seekGreen : .primary)
                Text("余额 \(entry.balance)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
