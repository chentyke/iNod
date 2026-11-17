import Foundation

actor ImageWorkLimiter {
    private static let downloads = ImageWorkLimiter()
    private static let decodes = ImageWorkLimiter()
    private var active = 0
    private var waiting: [(id: UUID, prioritized: Bool, continuation: CheckedContinuation<Void, Error>)] = []

    static func load<Value: Sendable>(
        prioritized: Bool = false,
        download: @Sendable () async throws -> Data,
        decode: @Sendable (Data) async throws -> Value
    ) async throws -> Value {
        try await downloads.acquire(prioritized: prioritized)
        let data: Data
        do {
            try Task.checkCancellation()
            data = try await download()
            // Hold the download slot while waiting for a decoder so responses cannot pile up in memory.
            try await decodes.acquire(prioritized: prioritized)
        } catch {
            await downloads.release()
            throw error
        }
        await downloads.release()
        return try await decodes.perform { try await decode(data) }
    }

    private func perform<Value: Sendable>(_ work: @Sendable () async throws -> Value) async throws -> Value {
        defer { release() }
        try Task.checkCancellation()
        return try await work()
    }

    private func acquire(prioritized: Bool) async throws {
        try Task.checkCancellation()
        if active < 4 {
            active += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let index = prioritized ? waiting.firstIndex(where: { !$0.prioritized }) : nil
                waiting.insert((id, prioritized, continuation), at: index ?? waiting.endIndex)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.id == id }) {
            waiting.remove(at: index).continuation.resume(throwing: CancellationError())
        }
    }
}
