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

    @Test func retryFromAnotherNetworkKeepsEarlierMeasurements() async throws {
        let previous = NodeSeekCore.NetworkQualityReport.sample(.partialFailure)
        let tester = tester { _, _ in
            Issue.record("A retry over another network should stop before sending requests")
            throw URLError(.cannotConnectToHost)
        }
        var report: NodeSeekCore.NetworkQualityReport?
        for await update in tester.run([.speed, .ipv6], continuing: previous) { report = update }
        let final = try #require(report)
        #expect(final.network == previous.network)
        #expect(final.ipv4 == previous.ipv4)
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
