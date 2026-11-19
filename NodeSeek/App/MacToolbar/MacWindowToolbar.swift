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
final class MacWindowToolbar: NSObject, NSToolbarDelegate, UITextFieldDelegate {
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
        case .search: toolbarItem = NSUIViewToolbarItem(itemIdentifier: identifier, uiView: searchCapsule(for: identifier))
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
        // The search field draws its own capsule; the toolbar's button bezel would box the text field in a second one.
        if case .search = item.kind { toolbarItem.isBordered = false } else { toolbarItem.isBordered = true }
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
            guard let capsule = searchCapsules[toolbarItem.itemIdentifier] else { return }
            capsule.configure(prompt: prompt, label: item.label, width: item.width)
            // Leave the field alone while the reader types; follow the page when it clears or changes the search.
            if !capsule.field.isFirstResponder, capsule.field.text != text { capsule.field.text = text }
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

    private var searchCapsules: [NSToolbarItem.Identifier: MacToolbarSearchCapsule] = [:]

    private func searchCapsule(for identifier: NSToolbarItem.Identifier) -> MacToolbarSearchCapsule {
        if let capsule = searchCapsules[identifier] { return capsule }
        let capsule = MacToolbarSearchCapsule()
        capsule.field.delegate = self
        capsule.field.addAction(UIAction { [weak self, weak capsule] _ in
            guard let self, let capsule, let entry = self.entry(for: capsule.field) else { return }
            self.model.updateSearchText(capsule.field.text ?? "", of: entry.item.id, in: entry.section)
        }, for: .editingChanged)
        searchCapsules[identifier] = capsule
        return capsule
    }

    private func entry(for field: UITextField) -> (section: MacToolbarSection, item: MacToolbarItem)? {
        guard let identifier = searchCapsules.first(where: { $0.value.field === field })?.key else { return nil }
        return shown[identifier]
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let entry = entry(for: textField) else { return true }
        model.perform(entry.item.id, in: entry.section)
        textField.resignFirstResponder()
        return false
    }

    @objc private func performItem(_ sender: NSToolbarItem) {
        guard let entry = shown[sender.itemIdentifier] else { return }
        model.perform(entry.item.id, in: entry.section)
    }
}

/// The feed's search field in the toolbar, drawn like the search bar above the list on iPhone and iPad: a capsule
/// with the magnifier in a button-wide slot and the prompt right after it. Its fill is the platter the toolbar
/// draws behind its own buttons, so it sits with them; UIKit's glass has nothing behind a toolbar item to refract
/// and comes out as a flat dark block.
final class MacToolbarSearchCapsule: UIView {
    let field = UITextField()
    /// The visible capsule. The toolbar lays the item out in Mac points but draws this view at the app's
    /// Catalyst scale, centred in that frame, so the capsule is sized in app points to fill the frame instead.
    private let capsule = UIView()
    private var widthConstraint: NSLayoutConstraint!
    private var capsuleWidthConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        capsule.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 45 / 255, alpha: 1)
                : UIColor(red: 235 / 255, green: 235 / 255, blue: 237 / 255, alpha: 1)
        }
        capsule.layer.cornerRadius = Self.height / 2
        capsule.layer.cornerCurve = .continuous
        capsule.translatesAutoresizingMaskIntoConstraints = false

        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass",
                                              withConfiguration: UIImage.SymbolConfiguration(font: font)))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isAccessibilityElement = false

        field.font = font
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .label
        field.borderStyle = .none
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.autocapitalizationType = .none
        field.translatesAutoresizingMaskIntoConstraints = false

        addSubview(capsule)
        capsule.addSubview(icon)
        capsule.addSubview(field)
        widthConstraint = widthAnchor.constraint(equalToConstant: Self.defaultWidth * Self.catalystScale)
        capsuleWidthConstraint = capsule.widthAnchor.constraint(equalToConstant: Self.defaultWidth)
        NSLayoutConstraint.activate([
            widthConstraint,
            heightAnchor.constraint(equalToConstant: Self.height * Self.catalystScale),
            capsuleWidthConstraint,
            capsule.heightAnchor.constraint(equalToConstant: Self.height),
            capsule.centerXAnchor.constraint(equalTo: centerXAnchor, constant: Self.toolbarInset),
            capsule.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
            icon.widthAnchor.constraint(equalToConstant: Self.iconSlot),
            icon.topAnchor.constraint(equalTo: capsule.topAnchor),
            icon.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor),
            field.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -14),
            field.topAnchor.constraint(equalTo: capsule.topAnchor),
            field.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
        ])
        // A click anywhere on the capsule starts typing, as on the search bar it stands in for.
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focus)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        capsule.frame.contains(point)
    }

    /// Sets the prompt and the capsule's width in app points.
    func configure(prompt: String, label: String, width: CGFloat?) {
        field.attributedPlaceholder = NSAttributedString(string: prompt, attributes: [.foregroundColor: UIColor.secondaryLabel])
        field.accessibilityLabel = label
        let width = width ?? Self.defaultWidth
        if capsuleWidthConstraint.constant != width {
            capsuleWidthConstraint.constant = width
            widthConstraint.constant = width * Self.catalystScale
        }
    }

    @objc private func focus() { field.becomeFirstResponder() }

    /// How much smaller a Catalyst app in the iPad idiom draws than the Mac points the toolbar lays out in.
    private static let catalystScale: CGFloat = 0.77
    /// The toolbar starts its first item this far short of the list's cards; nudging the capsule over lines their edges up.
    private static let toolbarInset: CGFloat = 8
    /// The width in a narrow window, where the field shares the toolbar with New Post and the category.
    private static let defaultWidth: CGFloat = 280
    /// As tall as the toolbar's buttons beside it.
    private static let height: CGFloat = 45
    /// The search bar's magnifier slot on iPhone and iPad.
    private static let iconSlot: CGFloat = 44
}
#endif
