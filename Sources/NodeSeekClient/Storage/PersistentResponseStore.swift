import CryptoKit
import Foundation

/// Keeps the latest feed and thread pages on disk, so a cold start can show them before the site answers.
/// Entries belong to one account; callers clear the store when the account changes.
@MainActor
final class PersistentResponseStore {
    struct Entry: Codable, Sendable {
        let kind: String
        let path: String
        let owner: Int?
        let date: Date
    }

    private let directory: URL
    private var index: [String: Entry]
    private let queue = DispatchQueue(label: "PersistentResponseStore", qos: .utility)
    private let maximumCount: Int
    private let lifetime: TimeInterval

    init(name: String = "SiteResponses", maximumCount: Int = 200, lifetime: TimeInterval = 7 * 24 * 3600) {
        directory = URL.cachesDirectory.appending(path: name, directoryHint: .isDirectory)
        self.maximumCount = maximumCount
        self.lifetime = lifetime
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = try? Data(contentsOf: directory.appending(path: Self.indexName))
        index = saved.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func data(kind: String, path: String, owner: Int?) -> Data? {
        let name = Self.fileName(kind: kind, path: path)
        guard let entry = index[name], entry.owner == owner, Date.now.timeIntervalSince(entry.date) < lifetime else { return nil }
        return try? Data(contentsOf: directory.appending(path: name))
    }

    func insert(_ data: Data, kind: String, path: String, owner: Int?) {
        let name = Self.fileName(kind: kind, path: path)
        index[name] = Entry(kind: kind, path: path, owner: owner, date: .now)
        var evicted: [String] = []
        while index.count > maximumCount, let oldest = index.min(by: { $0.value.date < $1.value.date })?.key {
            index[oldest] = nil
            evicted.append(oldest)
        }
        let directory = directory, snapshot = index
        queue.async { [evicted] in
            try? data.write(to: directory.appending(path: name), options: .atomic)
            for name in evicted { try? FileManager.default.removeItem(at: directory.appending(path: name)) }
            Self.save(snapshot, in: directory)
        }
    }

    func removeAll() {
        remove { _ in true }
    }

    func remove(where shouldRemove: (Entry) -> Bool) {
        let names = index.compactMap { shouldRemove($0.value) ? $0.key : nil }
        guard !names.isEmpty else { return }
        for name in names { index[name] = nil }
        let directory = directory, snapshot = index
        queue.async {
            for name in names { try? FileManager.default.removeItem(at: directory.appending(path: name)) }
            Self.save(snapshot, in: directory)
        }
    }

    nonisolated private static let indexName = "index.json"

    private static func fileName(kind: String, path: String) -> String {
        SHA256.hash(data: Data("\(kind)|\(path)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func save(_ index: [String: Entry], in directory: URL) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: directory.appending(path: indexName), options: .atomic)
    }
}
