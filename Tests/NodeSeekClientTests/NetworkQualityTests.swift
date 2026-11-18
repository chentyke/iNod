import Foundation
import Testing
@testable import NodeSeekClient

struct NetworkQualityTests {
    @Test func reportsSeparateIPFamiliesAndKeepsAddressWhenAttributionFails() async throws {
        let service = NetworkQualityService(request: { request, upload in
            let url = try #require(request.url)
            switch url.host() {
            case "api.ipify.org": return .init(body: Data("192.0.2.123\n".utf8))
            case "api6.ipify.org": return .init(body: Data("2001:db8::123".utf8))
            case "ipinfo.io":
                if url.path().contains("192.0.2.123") {
                    let json = #"{"ip":"192.0.2.123","country":"JP","org":"AS64496 Example Network"}"#
                    return .init(body: Data(json.utf8))
                }
                return .init(statusCode: 429)
            default: return try Self.speedResponse(request, upload: upload)
            }
        }, paths: { AsyncStream { $0.yield(.init(network: .wifi)) } })

        let report = await service.run()
        #expect(report.state == .completed)
        #expect(report.network == .wifi)
        #expect(report.completedStepCount == 5)
        guard case .measured(let ipv4) = report.ipv4, case .measured(let ipv6) = report.ipv6,
              case .measured(let location) = ipv4.attribution else {
            Issue.record("Expected both egress addresses and IPv4 attribution")
            return
        }
        #expect(ipv4.address == "192.0.2.123")
        #expect(location.asn == "AS64496")
        #expect(ipv6.address == "2001:db8::123")
        #expect(ipv6.attribution == .unavailable(.httpStatus(429)))
        #expect(ipv6.attributionSource?.endpoint.host() == "ipinfo.io")
        guard case .measured(let latency) = report.latency, case .measured(let upload) = report.upload else {
            Issue.record("Expected latency and upload samples")
            return
        }
        #expect(latency.samples.count == 5)
        #expect(latency.samples.allSatisfy { $0.connectionFamily == .ipv4 })
        #expect(abs((latency.milliseconds ?? 0) - 20) < 0.001)
        #expect(latency.jitterMilliseconds == 0)
        #expect(upload.megabitsPerSecond == 80)
        #expect(!upload.isEstimate)
        let encoded = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(NetworkQualityReport.self, from: encoded) == report)
    }

    @Test func rejectsWrongFamilyWhileOtherChecksProceed() async {
        let service = NetworkQualityService(request: { request, upload in
            if request.url?.host() == "api6.ipify.org" {
                return .init(body: Data("192.0.2.8".utf8))
            }
            return try Self.speedResponse(request, upload: upload)
        }, paths: { AsyncStream { $0.yield(.init(network: .cellular)) } })
        let report = await service.run()
        #expect(report.ipv6 == .unavailable(.wrongAddressFamily))
        #expect(report.completedStepCount == 5)
    }

    @Test func switchingNetworksCancelsInFlightRequestsAndKeepsCompletedChecks() async {
        let (events, continuation) = AsyncStream.makeStream(of: QualityNetworkPath.self)
        continuation.yield(.init(network: .wifi))
        let service = NetworkQualityService(request: { request, _ in
            if request.url?.host() == "api6.ipify.org" {
                continuation.yield(.init(network: .cellular))
                try await Task.sleep(for: .seconds(10))
            }
            throw URLError(.cannotFindHost)
        }, paths: { events })
        let report = await service.run()
        #expect(report.state == .interrupted(.networkChanged))
        #expect(report.network == .wifi)
        #expect(report.ipv4 == .unavailable(.hostUnreachable))
        #expect(report.ipv6 == .unavailable(.networkChanged))
        #expect(report.latency == .pending)
        #expect(report.completedStepCount == 1)
    }

    @Test func cancellingAndRetryingUseIndependentReports() async {
        let (started, continuation) = AsyncStream.makeStream(of: Void.self)
        let service = NetworkQualityService(request: { _, _ in
            continuation.yield(())
            try await Task.sleep(for: .seconds(10))
            throw URLError(.cannotFindHost)
        }, paths: { AsyncStream { $0.yield(.init(network: .wifi)) } })
        for _ in 0..<2 {
            let task = Task { await service.run() }
            var iterator = started.makeAsyncIterator()
            _ = await iterator.next()
            task.cancel()
            let report = await task.value
            #expect(report.state == .cancelled)
            #expect(report.ipv4 == .cancelled)
            #expect(report.ipv6 == .pending)
            #expect(report.finishedAt != nil)
        }
    }

    @Test func offlinePathDoesNotContactProviders() async {
        let service = NetworkQualityService(request: { _, _ in
            Issue.record("An offline report should make no HTTP requests")
            throw URLError(.notConnectedToInternet)
        }, paths: { AsyncStream { $0.yield(.init(network: .offline)) } })
        let report = await service.run()
        #expect(report.network == .offline)
        #expect(report.state == .interrupted(.offline))
    }

    @Test func jitterUsesConsecutiveSuccessfulSamplesOnTheSameNode() {
        let latency = QualityLatency(source: .init(provider: "Example", endpoint: URL(string: "https://example.com")!, checkedAt: .now), samples: [
            .init(checkedAt: .now, node: "HKG", milliseconds: 10, issue: nil),
            .init(checkedAt: .now, node: nil, milliseconds: nil, issue: .timedOut),
            .init(checkedAt: .now, node: "HKG", milliseconds: 30, issue: nil),
            .init(checkedAt: .now, node: "HKG", milliseconds: 36, issue: nil),
            .init(checkedAt: .now, node: "NRT", milliseconds: 50, issue: nil)
        ])
        #expect(latency.milliseconds == 33)
        #expect(latency.jitterMilliseconds == 6)
    }

    private static func speedResponse(_ request: URLRequest, upload: Data?) throws -> QualityHTTPResponse {
        let url = try #require(request.url)
        if let upload {
            #expect(request.httpMethod == "POST")
            #expect(upload.count == 1_000_000 || upload.count == 10_000_000)
            return .init(node: "HKG", requestToFirstByte: 1)
        }
        let bytes = url.query?.split(separator: "&").first { $0.hasPrefix("bytes=") }.flatMap { Int($0.dropFirst(6)) } ?? 0
        return .init(body: Data(count: bytes == 0 ? 67 : bytes), node: "HKG", requestToFirstByte: 0.025,
                     requestToEnd: 1.005, serverTime: 0.005, connectionFamily: .ipv4)
    }
}
