#if targetEnvironment(macCatalyst)
import SwiftUI

/// The head of the Mac sidebar: New Post, then the community feed's category menu.
/// On a desktop these sit beside the tabs they serve instead of taking a row above the list;
/// the feed's search sits in the window toolbar over the list instead.
///
/// Each control is drawn as one of the sidebar's own rows: the tab rows' height, corner, width and
/// icon and label columns, so the header and the tabs below read as one list.
struct MacSidebarHeader: View {
    let model: MacToolbarModel
    /// Brings the community feed forward before a control acts on it, since the sidebar shows on every tab.
    let showFeed: () -> Void

    var body: some View {
        let _ = model.revision
        VStack(spacing: MacSidebarMetrics.spacing) {
            Button {
                model.requestCompose()
            } label: {
                MacSidebarRow(systemImage: "square.and.pencil") {
                    Text("发布帖子").fontWeight(.semibold).foregroundStyle(Color.seekInk)
                }
            }
            .buttonStyle(MacSidebarButtonStyle())
            .accessibilityLabel("发布帖子")

            ForEach(model.items(in: .sidebar)) { item in
                switch item.kind {
                case .menu(let title, let sections):
                    MacSidebarMenu(item: item, title: title ?? item.label, sections: sections, showFeed: showFeed)
                case .button, .share, .search:
                    EmptyView()
                }
            }
        }
        // The system insets the header further than the tab rows; reach out to the rows' edges.
        .padding(.horizontal, -MacSidebarMetrics.headerOutset)
        .padding(.top, MacSidebarMetrics.top)
        .padding(.bottom, MacSidebarMetrics.bottom)
    }
}

/// Sizes shared by the sidebar header's rows, measured from the system tab rows beneath them.
enum MacSidebarMetrics {
    /// The system tab rows' height: a 32-point Mac sidebar row at Catalyst's 77% scale.
    static let rowHeight: CGFloat = 41.5
    /// The corner of the system row highlight.
    static let radius: CGFloat = 10
    /// How much wider the tab rows run than the header the system lays out.
    static let headerOutset: CGFloat = 8
    /// Centres icons on the tab icons' column and starts labels on the tab labels' column.
    static let leading: CGFloat = 12
    static let iconWidth: CGFloat = 26
    static let labelGap: CGFloat = 12
    static let trailing: CGFloat = 12
    /// Between header rows. With the system's own gap, `bottom` leaves twice this before the tabs.
    static let spacing: CGFloat = 8
    /// Lifts the first row's top edge level with the reader's first card.
    static let top: CGFloat = -4.5
    static let bottom: CGFloat = 8
}

/// One header row: an icon on the tab icons' column, then the content on the tab labels' column.
private struct MacSidebarRow<Content: View, Trailing: View>: View {
    let systemImage: String
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    init(systemImage: String, @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.systemImage = systemImage
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: MacSidebarMetrics.labelGap) {
            Image(systemName: systemImage)
                .imageScale(.large)
                // The tint the system gives the tab icons below.
                .foregroundStyle(Color.seekSidebarSelection)
                .frame(width: MacSidebarMetrics.iconWidth)
                .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .font(.body)
        .lineLimit(1)
        .padding(.leading, MacSidebarMetrics.leading)
        .padding(.trailing, MacSidebarMetrics.trailing)
        .frame(maxWidth: .infinity, minHeight: MacSidebarMetrics.rowHeight)
        .background(Color.seekCard, in: .rect(cornerRadius: MacSidebarMetrics.radius))
        .overlay {
            RoundedRectangle(cornerRadius: MacSidebarMetrics.radius)
                .strokeBorder(Color.seekHairline.opacity(0.6), lineWidth: 0.5)
        }
        .contentShape(.rect(cornerRadius: MacSidebarMetrics.radius))
    }
}

/// Dims a header row while it is pressed, like a sidebar row.
private struct MacSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct MacSidebarMenu: View {
    let item: MacToolbarItem
    let title: String
    let sections: [[MacToolbarMenuEntry]]
    let showFeed: () -> Void

    var body: some View {
        Menu {
            ForEach(sections.indices, id: \.self) { index in
                Section {
                    ForEach(sections[index]) { entry in
                        // A toggle draws the menu's own checkmark beside the current sort and category.
                        Toggle(entry.title, isOn: Binding(get: { entry.isOn }, set: { _ in
                            showFeed()
                            entry.action()
                        }))
                    }
                }
            }
        } label: {
            MacSidebarRow(systemImage: item.systemImage) {
                Text(title).foregroundStyle(Color.seekInk)
            } trailing: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .menuStyle(.button)
        .buttonStyle(MacSidebarButtonStyle())
        .accessibilityLabel(item.label)
    }
}
#endif
