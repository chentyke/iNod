import NodeSeekClient
import SwiftUI

@main
struct NodeSeekApp: App {
    @State private var account = makeAccount()
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
                .environment(account)
                .tint(.seekGreen)
                .preferredColorScheme(appearance.colorScheme)
                .task { await account.refresh() }
                .task(id:"\(scenePhase)|\(account.revision)") {
                    guard scenePhase == .active,account.isLoggedIn else { return }
                    while !Task.isCancelled {
                        await account.inbox.refreshUnread()
                        do { try await Task.sleep(for:.seconds(30)) } catch { return }
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(300)) } catch { return }
                        guard !Task.isCancelled else { return }
                        if account.isLoggedIn { await account.refresh() }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await account.refresh() } }
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
        .commands { CommandGroup(replacing: .newItem) { } }
    }
}
