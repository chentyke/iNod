import SwiftUI

struct OfficialSettingsLink: View {
    let title: String
    let anchor: String
    var description: String = ""
    @State private var showsWebsite = false
    var body: some View {
        Button { showsWebsite = true } label: {
            HStack(spacing:12) {
                VStack(alignment:.leading,spacing:5) { Text(title).foregroundStyle(.primary); if !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary) } }
                Spacer(); Image(systemName:"arrow.up.right.square").foregroundStyle(.secondary)
            }.padding(.vertical,4)
        }.sheet(isPresented:$showsWebsite) { WebsiteView(initialURL: URL(string:"https://www.nodeseek.com/setting#\(anchor)")!) }
    }
}
