import SwiftUI

struct SeekSectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.bold()).foregroundStyle(Color.seekInk)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
        .textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}
