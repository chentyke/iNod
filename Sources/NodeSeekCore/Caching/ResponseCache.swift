import Foundation

public struct ResponseCache<Key: Hashable> {
    private struct Entry {
        let data: Data
        let decoded: (any Decodable)?
        let bytes: Int
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
        entry(for: key, now: now, allowingStale: allowingStale)?.data
    }

    public mutating func decodedValue<Value: Decodable>(_ type: Value.Type, for key: Key, now: Date = .now, allowingStale: Bool = false) throws -> Value? {
        guard let entry = entry(for: key, now: now, allowingStale: allowingStale) else { return nil }
        if let value = entry.decoded as? Value { return value }
        return try JSONDecoder().decode(type, from: entry.data)
    }

    private mutating func entry(for key: Key, now: Date, allowingStale: Bool) -> Entry? {
        guard var entry = entries[key] else { return nil }
        let age = now.timeIntervalSince(entry.date)
        guard age >= 0, age < (allowingStale ? max(600, entry.lifetime) : entry.lifetime) else { return nil }
        access &+= 1
        entry.access = access
        entries[key] = entry
        return entry
    }

    public mutating func insert(_ data: Data, for key: Key, lifetime: TimeInterval, now: Date = .now) {
        insert(data, decoded: nil, for: key, lifetime: lifetime, now: now)
    }

    public mutating func insert(_ data: Data, decoded: (any Decodable)?, for key: Key, lifetime: TimeInterval, now: Date = .now) {
        remove(key)
        guard maximumCount > 0, data.count <= maximumBytes, lifetime > 0 else { return }
        // Estimate the decoded value's cost using the encoded size and charge both to the cache.
        let decoded = data.count <= maximumBytes / 2 ? decoded : nil
        let bytes = decoded == nil ? data.count : data.count * 2
        access &+= 1
        entries[key] = Entry(data: data, decoded: decoded, bytes: bytes, date: now, lifetime: lifetime, access: access)
        totalBytes += bytes
        while entries.count > maximumCount || totalBytes > maximumBytes {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            remove(oldest)
        }
    }

    public mutating func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key) { totalBytes -= entry.bytes }
    }

    public mutating func remove(where shouldRemove: (Key) -> Bool) {
        for key in entries.keys.filter(shouldRemove) { remove(key) }
    }

    public mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        totalBytes = 0
    }
}
