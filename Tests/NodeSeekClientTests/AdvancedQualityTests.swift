import Foundation
import Testing
@testable import NodeSeekClient

struct AdvancedQualityTests {
    @Test func websiteStatusesDescribeWhatTheRequestActuallyObserved() async {
        let results = await AdvancedNetworkQualityService.websiteAccess { request, _ in
            switch request.url?.host() {
            case "www.apple.com": return .init(statusCode: 200)
            case "www.google.com": return .init(statusCode: 302)
            case "www.youtube.com": return .init(statusCode: 451)
            case "github.com": return .init(statusCode: 403)
            default: throw URLError(.timedOut)
            }
        }
        #expect(results.map(\.result) == [
            .measured(.webpageAccessible(httpStatus: 200)), .measured(.redirected(httpStatus: 302)),
            .measured(.legallyRestricted(httpStatus: 451)), .unavailable(.httpStatus(403)), .unavailable(.timedOut)
        ])
    }

    @Test func ipListsKeepProviderResultsSeparateForEachFamily() async {
        let results = await QualityReputation.lookup(report: NetworkQualityExamples.completed) { request, _ in
            switch request.url?.path() {
            case "/drop/drop_v4.json":
                return .init(body: Data("""
                    {"cidr":"192.0.2.96/27","sblid":"SBL123"}
                    {"type":"metadata","timestamp":1700000000,"records":1}
                    """.utf8))
            case "/drop/drop_v6.json": throw URLError(.timedOut)
            default: return .init(body: Data("192.0.2.1\n2001:db8:1234:5678:abcd:ef01:2345:6789\n".utf8))
            }
        }
        #expect(results.map(\.family) == [.ipv4, .ipv6, .ipv4, .ipv6])
        #expect(results.map(\.result) == [.measured(.listed(reference: "SBL123")), .unavailable(.timedOut),
                                           .measured(.notListed), .measured(.listed(reference: nil))])
        #expect(results.allSatisfy { !$0.source.endpoint.absoluteString.contains("192.0.2.123") })
    }

    @Test func malformedAndTruncatedDropListsDoNotProduceACleanVerdict() {
        let incomplete = Data("{\"cidr\":\"192.0.2.0/24\",\"sblid\":\"SBL1\"}\n".utf8)
        #expect(throws: QualityIssue.invalidResponse) { try QualityReputation.dropVerdict(incomplete, bytes: [192, 0, 2, 100]) }
    }

    @Test func stunBindingRejectsRepliesFromAnotherTransactionAndTruncatedAttributes() throws {
        let transaction = Array(repeating: UInt8(27), count: 12)
        var response: [UInt8] = [1, 1, 0, 24, 0x21, 0x12, 0xa4, 0x42] + transaction
        response.append(contentsOf: [0, 0x20, 0, 8, 0, 1, 0xa0, 0x2a, 0xe1, 0x12, 0xa6, 0x39])
        response.append(contentsOf: [0x80, 0x2c, 0, 8, 0, 1, 0x01, 0xbb, 198, 51, 100, 8])
        let binding = try #require(QualitySTUN.parse(response, transaction: transaction))
        #expect(binding.mapped == .init(host: "192.0.2.123", port: 33080))
        #expect(binding.alternate == .init(host: "198.51.100.8", port: 443))
        #expect(QualitySTUN.parse(response, transaction: Array(repeating: 0, count: 12)) == nil)
        #expect(QualitySTUN.parse(Array(response.dropLast()), transaction: transaction) == nil)
    }

    @Test func hardwareCancellationRemovesTheFileAlreadyWritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (steps, continuation) = AsyncStream.makeStream(of: HardwareQualityReport.Step.self)
        let task = Task {
            await HardwareQualityService.benchmark(HardwareQualityService.makeReport(), in: directory) { report in
                if let step = report.currentStep { continuation.yield(step) }
                if report.currentStep == .read { try? await Task.sleep(for: .seconds(5)) }
            }
        }
        Task { _ = await task.value; continuation.finish() }
        var iterator = steps.makeAsyncIterator()
        for expected in [HardwareQualityReport.Step.cpu, .cpuMulti, .write, .read] {
            #expect(await iterator.next() == expected)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
        task.cancel()
        let report = await task.value
        #expect(report.state == .cancelled)
        #expect(report.read == .cancelled)
        #expect(report.cleanupIssue == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
