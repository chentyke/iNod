import NodeSeekClient
import SwiftUI

extension EnvironmentValues {
    @Entry var pageRefresh: PageRefreshController?
}

extension ScenePhase {
    /// Whether periodic foreground refreshes should keep running. On a Mac a window stays visible
    /// beside other apps while `.inactive`, and only stops when hidden or minimised (`.background`).
    var isPollingActive: Bool {
        #if targetEnvironment(macCatalyst)
        self != .background
        #else
        self == .active
        #endif
    }
}

extension View {
    /// Registers this page's reload action with the menu bar's manual refresh command while the view is visible.
    func menuRefreshable(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(MenuRefreshModifier(action: action))
    }
}

@MainActor
private final class RefreshActionBox {
    var action: (@MainActor () async -> Void)?
}

private struct MenuRefreshModifier: ViewModifier {
    let action: @MainActor () async -> Void
    @Environment(\.pageRefresh) private var pageRefresh
    @State private var id = UUID()
    @State private var box = RefreshActionBox()

    func body(content: Content) -> some View {
        box.action = action
        let box = box
        return content
            .onAppear {
                pageRefresh?.activate(id: id) { await box.action?() }
            }
            .onDisappear {
                pageRefresh?.deactivate(id: id)
            }
    }
}
