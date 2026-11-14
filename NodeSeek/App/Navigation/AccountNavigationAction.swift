import SwiftUI

struct AccountNavigationAction {
    let open: @MainActor (AccountDestination) -> Void

    @MainActor func callAsFunction(_ destination: AccountDestination) { open(destination) }
}

extension EnvironmentValues {
    @Entry var openAccountDestination = AccountNavigationAction { _ in }
}
