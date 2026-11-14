import Foundation
import Testing
@testable import NodeSeekCore

@Test func cacheExpiresButKeepsBriefFallback() {
    var cache = ResponseCache<String>()
    let start = Date(timeIntervalSince1970: 1000)
    let data = Data("response".utf8)
    cache.insert(data, for: "page", lifetime: 15, now: start)
    #expect(cache.value(for: "page", now: start.addingTimeInterval(14)) == data)
    #expect(cache.value(for: "page", now: start.addingTimeInterval(15)) == nil)
    #expect(cache.value(for: "page", now: start.addingTimeInterval(599), allowingStale: true) == data)
    #expect(cache.value(for: "page", now: start.addingTimeInterval(600), allowingStale: true) == nil)
    #expect(cache.value(for: "page", now: start.addingTimeInterval(-1), allowingStale: true) == nil)
}

@Test func cacheEvictsLeastRecentlyReadResponse() {
    var cache = ResponseCache<String>(maximumBytes: 8, maximumCount: 2)
    let data = Data(repeating: 1, count: 4)
    cache.insert(data, for: "first", lifetime: 60)
    cache.insert(data, for: "second", lifetime: 60)
    #expect(cache.value(for: "first") == data)
    cache.insert(data, for: "third", lifetime: 60)
    #expect(cache.value(for: "first") == data)
    #expect(cache.value(for: "second") == nil)
    #expect(cache.value(for: "third") == data)
    #expect(cache.totalBytes == 8)
    #expect(cache.count == 2)
}

@Test func cacheReplacementAndOversizedResponsesRespectMemoryLimit() {
    var cache = ResponseCache<Int>(maximumBytes: 6, maximumCount: 4)
    cache.insert(Data(repeating: 1, count: 4), for: 1, lifetime: 60)
    cache.insert(Data(repeating: 2, count: 2), for: 1, lifetime: 60)
    #expect(cache.totalBytes == 2)
    cache.insert(Data(repeating: 3, count: 7), for: 2, lifetime: 60)
    #expect(cache.count == 1)
    #expect(cache.totalBytes == 2)
    cache.insert(Data(repeating: 4, count: 5), for: 3, lifetime: 60)
    #expect(cache.value(for: 1) == nil)
    #expect(cache.totalBytes == 5)
    cache.remove(3)
    #expect(cache.totalBytes == 0)
}

@Test func cacheClearRemovesPrivateResponsesAndRejectsDisabledEntries() {
    var cache = ResponseCache<String>()
    cache.insert(Data("private".utf8), for: "account", lifetime: 60)
    cache.removeAll()
    #expect(cache.value(for: "account", allowingStale: true) == nil)
    #expect(cache.count == 0)
    #expect(cache.totalBytes == 0)
    cache.insert(Data([1]), for: "expired", lifetime: 0)
    #expect(cache.count == 0)
    var disabled = ResponseCache<String>(maximumBytes: 0, maximumCount: 0)
    disabled.insert(Data([1]), for: "page", lifetime: 60)
    #expect(disabled.count == 0)
}

@Test func cacheRemovesOnlyMatchingResponsesAndUpdatesByteCount() {
    var cache = ResponseCache<String>()
    cache.insert(Data(repeating: 1, count: 4), for: "thread-1", lifetime: 60)
    cache.insert(Data(repeating: 2, count: 3), for: "thread-2", lifetime: 60)
    cache.insert(Data(repeating: 3, count: 2), for: "notices", lifetime: 5)
    cache.remove { $0.hasPrefix("thread-") }
    #expect(cache.value(for: "thread-1", allowingStale: true) == nil)
    #expect(cache.value(for: "thread-2", allowingStale: true) == nil)
    #expect(cache.value(for: "notices") == Data(repeating: 3, count: 2))
    #expect(cache.count == 1)
    #expect(cache.totalBytes == 2)
    cache.remove { _ in false }
    #expect(cache.count == 1)
    #expect(cache.totalBytes == 2)
}
