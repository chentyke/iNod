#if targetEnvironment(macCatalyst)
import Observation
import SwiftUI
import UIKit

extension View {
    /// Gives the Mac window a native toolbar in place of its title strip. Pages fill it through `macToolbar(_:items:)`.
    func macWindowToolbar(_ model: MacToolbarModel) -> some View {
        background(MacWindowToolbarInstaller(model: model).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

private struct MacWindowToolbarInstaller: UIViewRepresentable {
    let model: MacToolbarModel

    func makeCoordinator() -> MacWindowToolbar { MacWindowToolbar(model: model) }
    func makeUIView(context: Context) -> HostView { HostView(toolbar: context.coordinator) }
    func updateUIView(_ view: HostView, context: Context) {}

    final class HostView: UIView {
        private let toolbar: MacWindowToolbar

        init(toolbar: MacWindowToolbar) {
            self.toolbar = toolbar
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let titlebar = window?.windowScene?.titlebar else { return }
            // The window title only repeated the app name; the toolbar takes the whole strip, lined up with the traffic lights.
            titlebar.titleVisibility = .hidden
            titlebar.toolbarStyle = .unified
            titlebar.toolbar = toolbar.toolbar
        }
    }
}

/// Mirrors `MacToolbarModel` into the window's `NSToolbar`.
///
/// Controls drawn by the app can't sit in the toolbar strip: the toolbar takes every click there to move the window.
/// So each page's controls become real toolbar items, which also gives them the standard Mac size and grouping.
@MainActor
final class MacWindowToolbar: NSObject, NSToolbarDelegate, UISearchTextFieldDelegate {
    let toolbar = NSToolbar(identifier: "iNod.window")
    private let model: MacToolbarModel
    /// The item each identifier currently shows, so a click finds its action and a refresh can update it in place.
    private var shown: [NSToolbarItem.Identifier: (section: MacToolbarSection, item: MacToolbarItem)] = [:]

    init(model: MacToolbarModel) {
        self.model = model
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        sync()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = model.revision
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
    }

    private static func identifier(_ section: MacToolbarSection, _ id: String) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("\(section).\(id)")
    }

    private func sync() {
        var next: [NSToolbarItem.Identifier: (MacToolbarSection, MacToolbarItem)] = [:]
        // Starts the page's items at the sidebar's edge, past the traffic lights and sidebar.
        var identifiers: [NSToolbarItem.Identifier] = model.tracksSidebar ? [.primarySidebarTrackingSeparatorItemIdentifier] : []
        for section in MacToolbarSection.toolbar {
            if section == .trailing { identifiers.append(.flexibleSpace) }
            for item in model.items(in: section) {
                let id = Self.identifier(section, item.id)
                next[id] = (section, item)
                identifiers.append(id)
            }
        }
        shown = next.mapValues { (section: $0.0, item: $0.1) }
        if toolbar.itemIdentifiers != identifiers {
            toolbar.itemIdentifiers = identifiers
        }
        // Items that stayed keep their NSToolbarItem; bring their look and menus up to date.
        for toolbarItem in toolbar.items {
            if let entry = shown[toolbarItem.itemIdentifier] {
                configure(toolbarItem, with: entry.item, in: entry.section)
            }
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.primarySidebarTrackingSeparatorItemIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.primarySidebarTrackingSeparatorItemIdentifier, .flexibleSpace] + Array(shown.keys)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let entry = shown[identifier] else { return nil }
        let toolbarItem: NSToolbarItem
        switch entry.item.kind {
        case .button: toolbarItem = NSToolbarItem(itemIdentifier: identifier)
        case .menu: toolbarItem = NSMenuToolbarItem(itemIdentifier: identifier)
        case .share: toolbarItem = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
        case .search: toolbarItem = NSUIViewToolbarItem(itemIdentifier: identifier, uiView: searchField(for: identifier))
        }
        configure(toolbarItem, with: entry.item, in: entry.section)
        return toolbarItem
    }

    private func configure(_ toolbarItem: NSToolbarItem, with item: MacToolbarItem, in section: MacToolbarSection) {
        toolbarItem.label = item.label
        toolbarItem.toolTip = item.label
        toolbarItem.isNavigational = item.isNavigational
        toolbarItem.autovalidates = false
        toolbarItem.isEnabled = item.isEnabled
        toolbarItem.isBordered = true
        let image = UIImage(systemName: item.systemImage)
        switch item.kind {
        case .button:
            toolbarItem.image = image
            toolbarItem.target = self
            toolbarItem.action = #selector(performItem(_:))
        case .menu(let title, let sections):
            guard let menuItem = toolbarItem as? NSMenuToolbarItem else { return }
            if let title {
                menuItem.title = title
                menuItem.image = nil
                menuItem.showsIndicator = true
            } else {
                menuItem.image = image
                menuItem.showsIndicator = false
            }
            menuItem.itemMenu = menu(sections, itemID: item.id, section: section)
        case .share(let url):
            guard let shareItem = toolbarItem as? NSSharingServicePickerToolbarItem else { return }
            shareItem.activityItemsConfiguration = UIActivityItemsConfiguration(objects: [url as NSURL])
        case .search(let prompt, let text):
            guard let field = (toolbarItem as? NSUIViewToolbarItem)?.uiView as? UISearchTextField else { return }
            field.placeholder = prompt
            field.accessibilityLabel = item.label
            // Leave the field alone while the reader types; follow the page when it clears or changes the search.
            if !field.isFirstResponder, field.text != text { field.text = text }
        }
    }

    private func menu(_ sections: [[MacToolbarMenuEntry]], itemID: String, section: MacToolbarSection) -> UIMenu {
        let groups = sections.map { entries in
            UIMenu(options: .displayInline, children: entries.map { entry in
                UIAction(title: entry.title,
                         image: entry.systemImage.flatMap { UIImage(systemName: $0) },
                         attributes: entry.isDestructive ? .destructive : [],
                         state: entry.isOn ? .on : .off) { [weak self] _ in
                    self?.model.performMenuEntry(entry.id, of: itemID, in: section)
                }
            })
        }
        return UIMenu(children: groups)
    }

    private var searchFields: [NSToolbarItem.Identifier: UISearchTextField] = [:]

    private func searchField(for identifier: NSToolbarItem.Identifier) -> UISearchTextField {
        if let field = searchFields[identifier] { return field }
        let field = UISearchTextField()
        field.delegate = self
        field.returnKeyType = .search
        // The toolbar item's glass capsule is the field; drop the text field's own filled background inside it.
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: Self.searchFieldWidth).isActive = true
        field.addAction(UIAction { [weak self, weak field] _ in
            guard let self, let field, let entry = self.entry(for: field) else { return }
            self.model.updateSearchText(field.text ?? "", of: entry.item.id, in: entry.section)
        }, for: .editingChanged)
        searchFields[identifier] = field
        return field
    }

    /// About as wide as the list's cards, so the field reads as the top of the list it searches.
    private static let searchFieldWidth: CGFloat = 256

    private func entry(for field: UISearchTextField) -> (section: MacToolbarSection, item: MacToolbarItem)? {
        guard let identifier = searchFields.first(where: { $0.value === field })?.key else { return nil }
        return shown[identifier]
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let field = textField as? UISearchTextField, let entry = entry(for: field) else { return true }
        model.perform(entry.item.id, in: entry.section)
        field.resignFirstResponder()
        return false
    }

    @objc private func performItem(_ sender: NSToolbarItem) {
        guard let entry = shown[sender.itemIdentifier] else { return }
        model.perform(entry.item.id, in: entry.section)
    }
}
#endif
