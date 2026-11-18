import Foundation
import Testing
@testable import NodeSeekClient

@MainActor
struct PageRefreshControllerTests {
    @Test func refreshesTopmostActivePageAcrossPushAndPop() async {
        let controller = PageRefreshController()
        #expect(!controller.canRefresh)

        var events: [String] = []
        let feedID = UUID()
        let threadID = UUID()

        controller.activate(id: feedID) { events.append("feed") }
        #expect(controller.canRefresh)
        await controller.refresh()
        #expect(events == ["feed"])

        // Even if the pushed page appears before the root page disappears, the pushed page wins.
        controller.activate(id: threadID) { events.append("thread") }
        controller.deactivate(id: feedID)
        await controller.refresh()
        #expect(events == ["feed", "thread"])

        // Popping back restores the root page regardless of appear/disappear order.
        controller.activate(id: feedID) { events.append("feed-returned") }
        controller.deactivate(id: threadID)
        await controller.refresh()
        #expect(events == ["feed", "thread", "feed-returned"])

        controller.deactivate(id: feedID)
        #expect(!controller.canRefresh)
    }

    @Test func updatesActionInPlaceAndIgnoresConcurrentRefresh() async {
        let controller = PageRefreshController()
        let firstID = UUID()
        let secondID = UUID()
        var seen: [String] = []

        controller.activate(id: firstID) { seen.append("first-1") }
        controller.activate(id: secondID) { seen.append("second") }
        controller.update(id: firstID) { seen.append("first-2") }

        // Updating `firstID` must not steal focus from `secondID`.
        await controller.refresh()
        #expect(seen == ["second"])

        controller.deactivate(id: secondID)
        await controller.refresh()
        #expect(seen == ["second", "first-2"])

        var startedContinuation: CheckedContinuation<Void, Never>?
        var finishContinuation: CheckedContinuation<Void, Never>?
        var slowRuns = 0
        controller.activate(id: secondID) {
            slowRuns += 1
            await withCheckedContinuation { finish in
                finishContinuation = finish
                startedContinuation?.resume()
            }
        }

        let inFlight = Task { await controller.refresh() }
        await withCheckedContinuation { startedContinuation = $0 }
        #expect(controller.isRefreshing)
        #expect(!controller.canRefresh)

        await controller.refresh()
        #expect(slowRuns == 1)

        finishContinuation?.resume()
        await inFlight.value
        #expect(!controller.isRefreshing)
        #expect(controller.canRefresh)
    }
}
