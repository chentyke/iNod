import Foundation

public struct ResponseCache<Key: Hashable> {
    private struct Entry {
        let data: Data
        let date: Date
        let lifetime: TimeInterval
        var access: UInt64
    }
    private var entries: [Key: Entry] = [:]
    private var access: UInt64 = 0
    private let maximumBytes: Int
    private let maximumCount: Int
    public private(set) var totalBytes = 0
    public var count: Int { entries.count }

    public init(maximumBytes: Int = 12_000_000, maximumCount: Int = 64) {
        self.maximumBytes = max(0, maximumBytes)
        self.maximumCount = max(0, maximumCount)
    }

    public mutating func value(for key: Key, now: Date = .now, allowingStale: Bool = false) -> Data? {
        guard var entry = entries[key] else { return nil }
        let age = now.timeIntervalSince(entry.date)
        guard age >= 0, age < (allowingStale ? max(600, entry.lifetime) : entry.lifetime) else { return nil }
        access &+= 1
        entry.access = access
        entries[key] = entry
        return entry.data
    }

    public mutating func insert(_ data: Data, for key: Key, lifetime: TimeInterval, now: Date = .now) {
        remove(key)
        guard maximumCount > 0, data.count <= maximumBytes, lifetime > 0 else { return }
        access &+= 1
        entries[key] = Entry(data: data, date: now, lifetime: lifetime, access: access)
        totalBytes += data.count
        while entries.count > maximumCount || totalBytes > maximumBytes {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            remove(oldest)
        }
    }

    public mutating func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key) { totalBytes -= entry.data.count }
    }

    public mutating func remove(where shouldRemove: (Key) -> Bool) {
        for key in entries.keys.filter(shouldRemove) { remove(key) }
    }

    public mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        totalBytes = 0
    }
}
