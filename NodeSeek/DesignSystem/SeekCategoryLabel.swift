import SwiftUI

struct SeekCategoryLabel: View {
    let title: String
    let category: String

    var body: some View {
        Text(title).font(.footnote.weight(.medium))
            .foregroundStyle(Color.categoryTint(category))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.categoryTint(category).opacity(0.08), in: .capsule)
    }
}
