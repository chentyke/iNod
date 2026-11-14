import Testing
@testable import NodeSeekClient

@MainActor
struct CollectionsServiceTests {
    @Test func oldPagesCannotOverwriteAnUpdatedBookmark() async throws {
        let collections = CollectionsService { _, _, _ in }
        collections.reset(userID: 4)
        let oldRevision = collections.revision
        collections.observe([10, 12], collected: true, expectedRevision: oldRevision)

        try await collections.setCollected(false, postID: 10)
        collections.observe([10, 11], collected: true, expectedRevision: oldRevision)

        #expect(collections.status(10) == false)
        #expect(collections.status(11) == true)
        #expect(collections.status(12) == true)
        #expect(collections.status(13) == nil)
        #expect(collections.updating.isEmpty)
    }

    @Test func oldBookmarkWriteCannotEnterANewSessionForTheSameUser() async throws {
        let site = PendingCollectionWrite()
        let collections = CollectionsService { _, _, _ in await site.suspendWrite() }
        collections.reset(userID: 4)
        let task = await site.startWrite { try await collections.setCollected(true, postID: 10) }
        #expect(collections.updating.contains(10))

        collections.reset(userID: nil)
        collections.reset(userID: 4)
        site.resumeWrite()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(collections.status(10) == nil)
        #expect(collections.updating.isEmpty)
    }
}

@MainActor
private final class PendingCollectionWrite {
    private var started: CheckedContinuation<Void, Never>?
    private var finish: CheckedContinuation<Void, Never>?

    func startWrite(_ operation: @escaping @MainActor () async throws -> Void) async -> Task<Void, any Error> {
        let task = Task { try await operation() }
        await withCheckedContinuation { started = $0 }
        return task
    }

    func suspendWrite() async {
        await withCheckedContinuation {
            finish = $0
            started?.resume()
            started = nil
        }
    }

    func resumeWrite() {
        finish?.resume()
        finish = nil
    }
}
