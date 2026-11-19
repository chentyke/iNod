import Observation
import SwiftUI

/// Where a page's controls sit in the Mac window.
enum MacToolbarSection {
    /// In the toolbar just past the sidebar, above the list or page the sidebar opened: back, the feed's search,
    /// and in a narrow window New Post and the category too.
    case leading
    /// At the toolbar's trailing edge, above the reader: actions on what is being read.
    case trailing
    /// At the head of the sidebar, under New Post: the community feed's category.
    /// It stays there while another tab is open, and using it goes back to the feed.
    case sidebar

    /// The sections the window toolbar shows, in order.
    static let toolbar: [MacToolbarSection] = [.leading, .trailing]
}

/// One control in the Mac window toolbar. Pages describe their controls with these and the window
/// turns them into native toolbar items, so a Mac reader gets buttons sized and placed like any Mac app's.
struct MacToolbarItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case button
        /// A pull-down menu. A title shows as text with a disclosure arrow, like a filter; without one the item shows its symbol.
        case menu(title: String?, sections: [[MacToolbarMenuEntry]])
        case share(URL)
        /// A search field. Typing reports each change through `onTextChange`; Return runs `action`.
        case search(prompt: String, text: String)
    }

    let id: String
    var label: String
    var image: ImageResource
    var kind: Kind = .button
    var isEnabled = true
    /// Back and other moves between pages sit at the toolbar's leading edge.
    var isNavigational = false
    /// A search field's width; nil keeps the toolbar's default.
    var width: CGFloat?
    var action: @MainActor () -> Void = {}
    var onTextChange: @MainActor (String) -> Void = { _ in }

    /// Items the menu bar mirrors with keyboard shortcuts.
    static let composeID = "compose"
    static let replyID = "reply"
    static let collectionID = "collection"

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.image == rhs.image
            && lhs.kind == rhs.kind && lhs.isEnabled == rhs.isEnabled && lhs.isNavigational == rhs.isNavigational
            && lhs.width == rhs.width
    }
}

struct MacToolbarMenuEntry: Identifiable, Equatable {
    let id: String
    var title: String
    var image: ImageResource?
    var isOn = false
    var isDestructive = false
    var action: @MainActor () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.image == rhs.image
            && lhs.isOn == rhs.isOn && lhs.isDestructive == rhs.isDestructive
    }
}

/// The controls each visible page has put in the window toolbar. The latest page to appear in a section owns it,
/// the way the menu bar's Refresh command follows the page on screen.
@MainActor
@Observable
final class MacToolbarModel {
    @MainActor
    final class Registration {
        let section: MacToolbarSection
        /// Rewritten on every render, so actions always call into the page's current state.
        var items: [MacToolbarItem]

        init(section: MacToolbarSection, items: [MacToolbarItem]) {
            self.section = section
            self.items = items
        }
    }

    private struct WeakRegistration {
        weak var value: Registration?
    }

    /// Held weakly: a page's view owns its registration, so a page that goes away takes its controls with it
    /// even where it never disappears first, as with the sidebar's.
    @ObservationIgnored private var registrations: [ObjectIdentifier: WeakRegistration] = [:]
    @ObservationIgnored private var order: [ObjectIdentifier] = []
    /// Bumped whenever what the toolbar shows changes.
    private(set) var revision = 0
    /// Bumped by the sidebar's New Post button and ⌘N. The community feed answers it, after the root view has switched to it.
    private(set) var composeRequests = 0

    func requestCompose() { composeRequests += 1 }

    /// Whether the tabs sit in a sidebar. Narrow windows move them to a tab bar, and the toolbar then has no sidebar edge to follow.
    var tracksSidebar = true {
        didSet { if tracksSidebar != oldValue { revision += 1 } }
    }

    /// The section's items from the latest page that has any. A page with nothing to show there leaves it to the page beneath.
    func items(in section: MacToolbarSection) -> [MacToolbarItem] {
        for id in order.reversed() {
            if let registration = registrations[id]?.value, registration.section == section, !registration.items.isEmpty {
                return registration.items
            }
        }
        return []
    }

    /// The visible item with `id` in `section`, for the menu bar commands that mirror toolbar buttons.
    func item(_ id: String, in section: MacToolbarSection) -> MacToolbarItem? {
        _ = revision
        return items(in: section).first { $0.id == id && $0.isEnabled }
    }

    func activate(_ registration: Registration) {
        let gone = registrations.filter { $0.value.value == nil }.keys
        order.removeAll { gone.contains($0) }
        for id in gone { registrations[id] = nil }
        let id = ObjectIdentifier(registration)
        registrations[id] = WeakRegistration(value: registration)
        order.removeAll { $0 == id }
        order.append(id)
        revision += 1
    }

    func deactivate(_ registration: Registration) {
        let id = ObjectIdentifier(registration)
        guard registrations.removeValue(forKey: id) != nil else { return }
        order.removeAll { $0 == id }
        revision += 1
    }

    /// Call after a registration's visible items changed.
    func refresh(_ registration: Registration) {
        guard registrations[ObjectIdentifier(registration)] != nil else { return }
        revision += 1
    }

    func perform(_ id: String, in section: MacToolbarSection) {
        item(id, in: section)?.action()
    }

    func updateSearchText(_ text: String, of itemID: String, in section: MacToolbarSection) {
        items(in: section).first { $0.id == itemID }?.onTextChange(text)
    }

    func performMenuEntry(_ entryID: String, of itemID: String, in section: MacToolbarSection) {
        guard case .menu(_, let sections)? = item(itemID, in: section)?.kind else { return }
        sections.joined().first { $0.id == entryID }?.action()
    }
}

extension View {
    /// Puts controls in the Mac window toolbar while this view is on screen, or at the head of the sidebar while the view exists.
    /// Other platforms keep their own bars and skip it.
    func macToolbar(_ section: MacToolbarSection, items: @autoclosure () -> [MacToolbarItem]) -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacToolbarRegistrationModifier(section: section, items: items()))
        #else
        self
        #endif
    }
}

extension View {
    /// Fades a scroll view's content out beneath the Mac window toolbar. Under the toolbar the system's scroll edge
    /// is a hard-edged band, which looked like a second bar over each column.
    func fadesUnderMacToolbar() -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacToolbarFade())
        #else
        self
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct MacToolbarFade: ViewModifier {
    @State private var toolbarHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(true, for: .top)
            .mask {
                // Clear under the toolbar's buttons, then fade in over the gap above the first card.
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(0, toolbarHeight - 16))
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    Color.black
                }
                .ignoresSafeArea()
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { toolbarHeight = $0 }
    }
}

private struct MacToolbarRegistrationModifier: ViewModifier {
    let section: MacToolbarSection
    let items: [MacToolbarItem]
    @Environment(MacToolbarModel.self) private var model: MacToolbarModel?
    @State private var registration: MacToolbarModel.Registration?

    func body(content: Content) -> some View {
        registration?.items = items
        return content
            .onAppear {
                let registration = registration ?? MacToolbarModel.Registration(section: section, items: items)
                self.registration = registration
                model?.activate(registration)
            }
            .onDisappear {
                // The sidebar shows on every tab, so its controls outlast a switch to another tab.
                if section != .sidebar, let registration { model?.deactivate(registration) }
            }
            .onChange(of: items) {
                if let registration { model?.refresh(registration) }
            }
    }
}
#endif
