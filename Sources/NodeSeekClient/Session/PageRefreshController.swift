import Foundation
import Observation

/// Tracks the visible screen's refresh action so the menu bar and keyboard shortcut reload whichever page is open.
@MainActor
@Observable
public final class PageRefreshController {
    private struct Entry {
        let id: UUID
        let action: @MainActor () async -> Void
    }

    @ObservationIgnored private var entries: [Entry] = []
    private var hasActiveEntry = false
    public private(set) var isRefreshing = false

    public init() {}

    public var canRefresh: Bool { hasActiveEntry && !isRefreshing }

    public func activate(id: UUID, action: @escaping @MainActor () async -> Void) {
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, action: action))
        if !hasActiveEntry { hasActiveEntry = true }
    }

    public func update(id: UUID, action: @escaping @MainActor () async -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index] = Entry(id: id, action: action)
    }

    public func deactivate(id: UUID) {
        entries.removeAll { $0.id == id }
        let hasEntries = !entries.isEmpty
        if hasActiveEntry != hasEntries { hasActiveEntry = hasEntries }
    }

    public func refresh() async {
        guard !isRefreshing, let current = entries.last else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await current.action()
    }
}
