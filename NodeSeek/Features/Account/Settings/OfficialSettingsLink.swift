import NodeSeekCore
import SwiftUI

/// A row that opens a section of the website's settings in the reader's browser.
struct OfficialSettingsLink: View {
    let title: String
    let anchor: String
    var description: String = ""
    var body: some View {
        Button { Browser.open(NodeSeekRoute.settings(section: anchor).url) } label: {
            HStack(spacing:12) {
                VStack(alignment:.leading,spacing:5) { Text(title).foregroundStyle(.primary); if !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary) } }
                Spacer(); Image(systemName:"arrow.up.right.square").foregroundStyle(.secondary)
            }.padding(.vertical,4)
        }
    }
}
