public func appendPage<Page, Item: Identifiable>(_ items: WritableKeyPath<Page, [Item]>) -> (Page, Page) -> Page {
    { previous, next in
        let existing = previous[keyPath: items]
        var ids = Set(existing.map(\.id))
        var combined = next
        combined[keyPath: items] = existing + next[keyPath: items].filter { ids.insert($0.id).inserted }
        return combined
    }
}
