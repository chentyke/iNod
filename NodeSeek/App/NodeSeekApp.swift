import NodeSeekClient
import SwiftUI

@main
struct NodeSeekApp: App {
    @State private var account = makeAccount()
    @State private var pageRefresh = PageRefreshController()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = AppAppearance.system

    private static func makeAccount() -> AccountSession {
        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["NODESEEK_UI_TEST_WEBSITE"] {
            do { return try AccountSession.fixtureForUITests(fixture) }
            catch { preconditionFailure("Invalid UI test website fixture: \(error)") }
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-offline") {
            return AccountSession.offlineForUITests()
        }
        #endif
        return AccountSession()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(UITestDynamicTypeModifier())
                .environment(account)
                .environment(\.pageRefresh, pageRefresh)
                .tint(.seekGreen)
                .preferredColorScheme(appearance.colorScheme)
                .task { await account.refresh() }
                .task(id: "\(scenePhase.isPollingActive)|\(account.revision)") {
                    guard scenePhase.isPollingActive, account.isLoggedIn else { return }
                    while !Task.isCancelled {
                        await account.inbox.refreshUnread()
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    }
                }
                .task(id: scenePhase.isPollingActive) {
                    guard scenePhase.isPollingActive else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(300)) } catch { return }
                        guard !Task.isCancelled else { return }
                        if account.isLoggedIn { await account.refresh() }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await account.refresh()
                            if account.isLoggedIn { await account.inbox.refreshUnread() }
                        }
                    }
                }
                #if targetEnvironment(macCatalyst)
                // Narrower than this, the feed's filter bar and the thread's reply bar start to crowd.
                .frame(minWidth: 400, minHeight: 560)
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .windowResizability(.contentMinSize)
        #endif
        // One window is enough, and ⌘N starts a new post instead of opening another window.
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                RefreshCommandButton(pageRefresh: pageRefresh)
            }
        }
    }
}

private struct RefreshCommandButton: View {
    let pageRefresh: PageRefreshController

    var body: some View {
        Button("刷新") {
            Task { await pageRefresh.refresh() }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(!pageRefresh.canRefresh)
    }
}

private struct UITestDynamicTypeModifier: ViewModifier {
    #if DEBUG
    private var overrideSize: DynamicTypeSize? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-UIPreferredContentSizeCategoryName"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        let raw = arguments[index + 1]
        if let mapped = DynamicTypeSize(UIContentSizeCategory(rawValue: raw)) {
            return mapped
        }
        switch raw {
        case "UICTContentSizeCategoryAccessibilityMedium": return .accessibility1
        case "UICTContentSizeCategoryAccessibilityLarge": return .accessibility2
        case "UICTContentSizeCategoryAccessibilityExtraLarge": return .accessibility3
        case "UICTContentSizeCategoryAccessibilityExtraExtraLarge": return .accessibility4
        case "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge": return .accessibility5
        default: return nil
        }
    }
    #endif

    func body(content: Content) -> some View {
        #if DEBUG
        if let size = overrideSize {
            content.dynamicTypeSize(size)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
