import SwiftUI

struct AppNavigationAction {
    let open: @MainActor (AppDestination) -> Void

    @MainActor func callAsFunction(_ destination: AppDestination) { open(destination) }
}

extension EnvironmentValues {
    @Entry var openAppDestination = AppNavigationAction { _ in }
}
