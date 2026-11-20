import NodeSeekCore
import SwiftUI

/// A row that opens a section of the website's settings in the reader's browser.
struct OfficialSettingsLink: View {
    let title: String
    var symbol: ImageResource = .inkWebsite
    let anchor: String
    var description: String = ""

    var body: some View {
        Button {
            Browser.open(NodeSeekRoute.settings(section: anchor).url)
        } label: {
            HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                SeekIconTile(symbol: symbol)
                VStack(alignment: .leading, spacing: AccountSettingsMetrics.rowLineSpacing) {
                    Text(title)
                        .foregroundStyle(Color.seekInk)
                    if !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(.inkOpenExternal)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.seekButtonIcon)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.seekRow)
        .accessibilityElement(children: .combine)
        .accessibilityHint("在系统浏览器中打开 NodeSeek 官网设置")
    }
}
