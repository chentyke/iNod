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
        let result = await HardwareQualityService.benchmark(HardwareQualityService.makeReport(), in: directory)
        let report = LiveDeviceBenchmark.report(result)
        #expect(report.isComplete)
        #expect(report.cpuMulti.value?.threads == result.processorCount)
        #expect(report.storageSequential.value?.blockSize == 1_048_576)
        #expect(report.storageRandom.value?.blockSize == 4096)
        #expect((report.storageRandom.value?.readIOPS ?? 0) > 0)
        #expect((report.storageRandom.value?.writeIOPS ?? 0) > 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    private func tester(request: @escaping QualityHTTP.Request) -> LiveNetworkQualityTester {
        let paths: @Sendable () -> AsyncStream<QualityNetworkPath> = { AsyncStream { $0.yield(.init(network: .wifi)) } }
        return LiveNetworkQualityTester(basics: NetworkQualityService(request: request, paths: paths), paths: paths)
    }
}
