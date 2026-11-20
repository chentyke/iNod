import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

@MainActor
struct AccountSessionTests {
    @Test(arguments: [true, false])
    func pendingActionWaitsForTheExistingLoginCheck(signedIn: Bool) async throws {
        let response = try snapshot(signedIn: signedIn)
        let (started, start) = AsyncStream<Void>.makeStream()
        let (results, result) = AsyncStream<AuthenticationSnapshot>.makeStream()
        var requests = 0
        let account = session { _ in
            requests += 1
            start.yield(())
            var iterator = results.makeAsyncIterator()
            return try #require(await iterator.next())
        }
        let refresh = Task { await account.refresh() }
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()

        let (tapped, tap) = AsyncStream<Void>.makeStream()
        var events: [String] = []
        let action = Task {
            tap.yield(())
            try await account.withConfirmedSignIn(onSignedOut: { events.append("login") }) { user in
                events.append("open-\(user.id)")
            }
        }
        var tappedIterator = tapped.makeAsyncIterator()
        _ = await tappedIterator.next()
        #expect(account.signInStatus == .unconfirmed)
        #expect(events.isEmpty)

        result.yield(response)
        result.finish()
        try await action.value
        await refresh.value
        #expect(account.signInStatus == (signedIn ? .signedIn : .signedOut))
        #expect(events == (signedIn ? ["open-42"] : ["login"]))
        #expect(requests == 1)
    }

    @Test func failedConfirmationCanBeRetriedWithoutOpeningLogin() async throws {
        let response = try snapshot(signedIn: true)
        var attempts = 0
        let account = session { force in
            #expect(force)
            attempts += 1
            if attempts == 1 { throw SiteError.message("暂时无法连接") }
            return response
        }
        var openedEditor = false
        var openedLogin = false
        func open() async throws {
            try await account.withConfirmedSignIn(onSignedOut: { openedLogin = true }) { _ in
                openedEditor = true
            }
        }

        await #expect(throws: SiteError.self) { try await open() }
        #expect(account.signInStatus == .unconfirmed)
        #expect(!openedEditor && !openedLogin)

        try await open()
        #expect(openedEditor && !openedLogin)
        #expect(attempts == 2)
    }

    @Test func leavingTheScreenWhileWaitingDoesNotOpenEitherScreen() async throws {
        let response = try snapshot(signedIn: true)
        let (started, start) = AsyncStream<Void>.makeStream()
        let (results, result) = AsyncStream<AuthenticationSnapshot>.makeStream()
        let account = session { _ in
            start.yield(())
            var iterator = results.makeAsyncIterator()
            return try #require(await iterator.next())
        }
        var opened = false
        let action = Task {
            try await account.withConfirmedSignIn(onSignedOut: { opened = true }) { _ in opened = true }
        }
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()
        action.cancel()
        result.yield(response)
        result.finish()

        await #expect(throws: CancellationError.self) { try await action.value }
        #expect(account.signInStatus == .signedIn)
        #expect(!opened)
    }

    private func session(load: @escaping @MainActor (Bool) async throws -> AuthenticationSnapshot) -> AccountSession {
        AccountSession(website: SiteDataStore(disk: nil), loadAuthentication: load)
    }

    private func snapshot(signedIn: Bool) throws -> AuthenticationSnapshot {
        let user = signedIn ? #"{"id":42,"name":"Test user"}"# : "null"
        return try JSONDecoder().decode(AuthenticationSnapshot.self, from: Data("{\"ready\":true,\"user\":\(user)}".utf8))
    }
}
