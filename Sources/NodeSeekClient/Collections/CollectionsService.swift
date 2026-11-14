import Observation

@MainActor
@Observable
public final class CollectionsService {
    public private(set) var updating: Set<Int> = []
    public private(set) var revision = 0
    private var states: [Int: (collected: Bool, changedAt: Int)] = [:]
    private var userID: Int?
    private var session = 0
    private let write: @MainActor (Int, Int, Bool) async throws -> Void

    init(write: @escaping @MainActor (Int, Int, Bool) async throws -> Void) { self.write = write }

    func reset(userID: Int?) {
        session += 1
        revision += 1
        self.userID = userID
        updating.removeAll()
        states.removeAll()
    }

    public func status(_ postID: Int) -> Bool? { states[postID]?.collected }

    public func observe(_ postIDs: [Int], collected: Bool, expectedRevision: Int) {
        guard userID != nil else { return }
        for postID in postIDs {
            let changedAt = states[postID]?.changedAt ?? 0
            if changedAt <= expectedRevision { states[postID] = (collected, changedAt) }
        }
    }

    public func setCollected(_ collected: Bool, postID: Int) async throws {
        guard let userID else { throw CancellationError() }
        guard updating.insert(postID).inserted else { return }
        let expectedSession = session
        defer { if session == expectedSession { updating.remove(postID) } }
        do {
            try await write(userID, postID, collected)
            guard session == expectedSession else { throw CancellationError() }
            revision += 1
            states[postID] = (collected, revision)
        } catch {
            guard session == expectedSession else { throw CancellationError() }
            throw error
        }
    }
}
