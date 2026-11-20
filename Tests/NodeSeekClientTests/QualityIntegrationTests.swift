import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

struct QualityIntegrationTests {
    @Test func retryingAnUploadKeepsTheEarlierDownloadAndDoesNotSendOtherRequests() async throws {
        var previous = NodeSeekCore.NetworkQualityReport.sample(.partialFailure)
        previous.network = .init(kind: .wifi)
        let plan = LiveNetworkQualityTester.basicSteps([.speed], previous: previous)
        #expect(plan == [.upload])
        let tester = tester { request, upload in
            #expect(request.url?.path() == "/__up")
            #expect(upload != nil)
            return .init(node: "HKG", requestToFirstByte: 1)
        }
        var report: NodeSeekCore.NetworkQualityReport?
        var showedSpeed = false
        for await update in tester.run([.speed], continuing: previous) {
            report = update
            if case .running(let progress) = update.speed, progress.currentMbps != nil { showedSpeed = true }
        }
        let final = try #require(report)
        #expect(showedSpeed)
        #expect(final.finishedAt != nil)
        #expect(final.speed.value?.uploadMbps == 80)
        #expect(final.speed.value?.downloadMbps == previous.speed.value?.downloadMbps)
        #expect(final.speed.value?.latencyMs == previous.speed.value?.latencyMs)
        #expect(final.ipv4 == previous.ipv4)
        #expect(final.routes == previous.routes)
    }

    @Test func completedSpeedReportIncludesAllMeasurementsAndRequiresNoRetry() async throws {
        let service = tester { request, upload in
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let bytes = query?.first { $0.name == "bytes" }?.value.flatMap(Int.init) ?? 0
            return .init(body: Data(count: bytes), node: "HKG", requestToFirstByte: upload == nil ? 0.025 : 1,
                         requestToEnd: 1, connectionFamily: .ipv4)
        }
        var last: NodeSeekCore.NetworkQualityReport?
        for await update in service.run([.speed], continuing: nil) { last = update }
        let report = try #require(last)
        let speed = try #require(report.speed.value)
        #expect(speed.downloadMbps == 80 && speed.uploadMbps == 80)
        #expect(speed.latencyMs == 25 && speed.jitterMs == 0 && speed.latencySamples == 5)
        #expect(speed.issues.isEmpty && report.retryableSteps.isEmpty)
    }

    @Test func retryPreservesLatencyWhenEverySubtestNeedsAnotherAttempt() async throws {
        let first = tester { request, _ in
            if request.url?.query?.split(separator: "&").contains("bytes=0") == true {
                // Different nodes make a latency median possible without a comparable jitter sample.
                return .init(node: UUID().uuidString, requestToFirstByte: 0.025)
            }
            return .init(statusCode: 429)
        }
        var initial: NodeSeekCore.NetworkQualityReport?
        for await update in first.run([.speed], continuing: nil) { initial = update }
        let partial = try #require(initial)
        let before = try #require(partial.speed.value)
        #expect(before.latencyMs == 25)
        #expect(before.jitterMs == nil)
        #expect(partial.retryableSteps == [.speed])

        let failing = tester { _, _ in .init(statusCode: 429) }
        var retried: NodeSeekCore.NetworkQualityReport?
        for await update in failing.run(partial.retryableSteps, continuing: partial) { retried = update }
        let result = try #require(retried?.speed.value)
        #expect(result.latencyMs == before.latencyMs)
        #expect(result.latencySamples == before.latencySamples)
        #expect(result.downloadMbps == nil)
        #expect(result.uploadMbps == nil)
    }

    @Test func serviceRetryReplacesOnlyTheFailedWebsiteInTheReport() async throws {
        let empty = NodeSeekCore.NetworkQualityReport(startedAt: .now, network: .init(kind: .wifi))
        let first = await LiveNetworkQualityTester.measureAdvanced(.services, in: empty, previous: nil) { request, _ in
            .init(statusCode: request.url?.host() == "github.com" ? 503 : 200)
        }
        let sites = try #require(first.services.value)
        #expect(sites.count == 5)
        #expect(sites.filter { $0.issue != nil }.map(\.name) == ["GitHub"])
        let retried = await LiveNetworkQualityTester.measureAdvanced(.services, in: first.resetting([.services]), previous: first) { request, _ in
            #expect(request.url?.host() == "github.com")
            return .init(statusCode: 200)
        }
        let updated = try #require(retried.services.value)
        #expect(updated.map(\.name) == sites.map(\.name))
        #expect(updated.filter { $0.name != "GitHub" } == sites.filter { $0.name != "GitHub" })
        #expect(updated.allSatisfy { $0.issue == nil && $0.outcome == .reachable })
    }

    @Test func reputationRetryLooksUpEverySourceWhenTheAddressChanges() async throws {
        var previous = NodeSeekCore.NetworkQualityReport.sample(.partialFailure)
        let oldIP = try #require(previous.ipv4.value)
        previous.reputation = .measured([
            .init(source: "Spamhaus DROP", family: .v4, verdict: .listed, queriedAt: oldIP.queriedAt),
            .init(source: "Blocklist.de", family: .v4, verdict: .unknown, queriedAt: oldIP.queriedAt, issue: .init(.timedOut))
        ])
        var retry = previous.resetting([.reputation])
        var newIP = oldIP
        newIP.address = "192.0.2.80"
        retry.ipv4 = .measured(newIP)
        let result = await LiveNetworkQualityTester.measureAdvanced(.reputation, in: retry, previous: previous) { request, _ in
            if request.url?.host() == "www.spamhaus.org" {
                return .init(body: Data("{\"cidr\":\"203.0.113.0/24\"}\n{\"timestamp\":1,\"records\":1}".utf8))
            }
            #expect(request.url?.host() == "lists.blocklist.de")
            return .init(body: Data("203.0.113.1".utf8))
        }
        let records = try #require(result.reputation.value)
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.verdict == .notListed && $0.issue == nil })
    }

    @Test func retryFromAnotherNetworkKeepsEarlierMeasurements() async throws {
        let previous = NodeSeekCore.NetworkQualityReport.sample(.partialFailure)
        let tester = tester { _, _ in
            Issue.record("A retry over another network should stop before sending requests")
            throw URLError(.cannotConnectToHost)
        }
        var report: NodeSeekCore.NetworkQualityReport?
        for await update in tester.run([.speed, .ipv4, .ipv6, .routes, .reputation], continuing: previous) { report = update }
        let final = try #require(report)
        #expect(final.network == previous.network)
        #expect(final.ipv4.value?.address == previous.ipv4.value?.address)
        #expect(final.ipv4.value?.ownerIssue?.kind == .networkChanged)
        #expect(final.routes.value?.filter { $0.issue == nil } == previous.routes.value?.filter { $0.issue == nil })
        #expect(final.routes.value?.last?.issue?.kind == .networkChanged)
        #expect(final.reputation.value?.filter { $0.issue == nil } == previous.reputation.value?.filter { $0.issue == nil })
        #expect(final.speed.value?.downloadMbps == previous.speed.value?.downloadMbps)
        #expect(final.ipv6 == .failed(.init(.networkChanged)))
    }

    @Test func onlySelectedBasicChecksRun() async throws {
        let tester = tester { request, _ in
            switch request.url?.host() {
            case "api.ipify.org": return .init(body: Data("192.0.2.80".utf8))
            case "ipinfo.io": return .init(body: Data(#"{"ip":"192.0.2.80","country":"JP","org":"AS64496 Example"}"#.utf8))
            default:
                Issue.record("An unselected service received a request")
                throw URLError(.cannotConnectToHost)
            }
        }
        var report: NodeSeekCore.NetworkQualityReport?
        for await update in tester.run([.ipv4], continuing: nil) { report = update }
        let final = try #require(report)
        #expect(final.includedSteps == [.ipv4])
        #expect(final.ipv4.value?.address == "192.0.2.80")
        #expect(final.ipv4.value?.owner?.asn == 64496)
        #expect(final.isFinished)
    }

    @Test func allHardwareMeasurementsProduceACompleteReportAndCleanUp() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = await HardwareQualityService.benchmark(
            HardwareQualityService.makeReport(), in: directory,
            workload: .init(cpuBytes: 4 * 1_048_576, storageBytes: 2 * 1_048_576, randomOperations: 16)
        )
        let report = LiveDeviceBenchmark.report(result)
        #expect(report.isComplete)
        #expect(report.cpuMulti.value?.threads == result.processorCount)
        #expect(report.storageSequential.value?.blockSize == 1_048_576)
        #expect(report.storageRandom.value?.blockSize == 4096)
        #expect((report.storageRandom.value?.readIOPS ?? 0) > 0)
        #expect((report.storageRandom.value?.writeIOPS ?? 0) > 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func ipDetailsMapTypesAndKeepEarlierAnswersOnRetry() async throws {
        var previous = NodeSeekCore.NetworkQualityReport.sample(.partialFailure)
        let address = try #require(previous.ipv4.value?.address)
        // First pass: RIPEstat answers, IPQuery is rate limited.
        let first = await LiveNetworkQualityTester.measureAdvanced(.ipDetails, in: previous, previous: nil) { request, _ in
            if request.url?.host() == "stat.ripe.net" {
                return .init(body: Data(#"{"status":"ok","data":{"asns":["64496"],"prefix":"198.51.100.0/24"}}"#.utf8))
            }
            return .init(statusCode: 429)
        }
        let profile = try #require(first.ipDetails.value?.first)
        #expect(first.ipDetails.value?.count == 1, "No IPv6 was measured, so only IPv4 is looked up")
        #expect(profile.route.result.value == BGPRoute(prefix: "198.51.100.0/24", originASNs: [64496]))
        #expect(profile.usage.result == .failed(.init(.rateLimited)))
        #expect(first.retryableSteps.contains(.ipDetails))

        // Retry: RIPEstat now fails, IPQuery answers. The earlier route stays.
        previous = first
        let retried = await LiveNetworkQualityTester.measureAdvanced(.ipDetails, in: first.resetting([.ipDetails]), previous: previous) { request, _ in
            if request.url?.host() == "api.ipquery.io" {
                return .init(body: Data(#"{"ip":"\#(address)","risk":{"risk_score":12,"is_mobile":true,"is_vpn":false,"is_datacenter":false}}"#.utf8))
            }
            throw URLError(.timedOut)
        }
        let merged = try #require(retried.ipDetails.value?.first)
        #expect(merged.route == profile.route)
        #expect(merged.usage.result.value == IPUsage(score: 12, tags: [.mobile], unreported: [.proxy, .tor]))
        #expect(!retried.retryableSteps.contains(.ipDetails))
    }

    private func tester(request: @escaping QualityHTTP.Request) -> LiveNetworkQualityTester {
        let paths: @Sendable () -> AsyncStream<QualityNetworkPath> = { AsyncStream { $0.yield(.init(network: .wifi)) } }
        return LiveNetworkQualityTester(basics: NetworkQualityService(request: request, paths: paths), paths: paths)
    }
}
