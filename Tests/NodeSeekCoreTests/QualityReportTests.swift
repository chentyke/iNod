import Foundation
import Testing
@testable import NodeSeekCore

struct QualityReportTests {
    @Test func cancellingKeepsFinishedResults() {
        var report = NetworkQualityReport.sample(.complete)
        report.ipv6 = .running(.init(fraction: 0.5))
        report.routes = .pending
        let cancelled = report.cancellingUnfinished()
        #expect(cancelled.speed == report.speed)
        #expect(cancelled.ipv6 == .cancelled)
        #expect(cancelled.routes == .cancelled)
        #expect(cancelled.isFinished)
    }

    @Test func retryResetsOnlyChosenSteps() {
        let report = NetworkQualityReport.sample(.partialFailure).resetting([.services])
        #expect(report.services == .pending)
        #expect(report.speed.value != nil)
        #expect(report.finishedAt == nil)
    }

    @Test func retryCoversPartlyMeasuredSteps() {
        #expect(NetworkQualityReport.sample(.partialFailure).retryableSteps == [.speed, .ipv4, .routes, .reputation, .services])
        #expect(NetworkQualityReport.sample(.complete).retryableSteps.isEmpty)
    }

    @Test func maskedAddressesHideTheSubscriber() {
        #expect(QualityFormat.masked("203.0.113.24") == "203.0.*.*")
        #expect(QualityFormat.masked("2001:db8:4c2a:1f00::1") == "2001:db8:*:*")
    }

    @Test func sharedTextHidesAddressesWhenAsked() {
        let report = NetworkQualityReport.sample(.complete)
        let hidden = report.sharedText(hidingAddresses: true, timeZone: .gmt)
        #expect(!hidden.contains("203.0.113.24"))
        #expect(hidden.contains("203.0.*.*"))
        #expect(hidden.contains("下载 486 Mbps"))
        #expect(report.sharedText(hidingAddresses: false, timeZone: .gmt).contains("203.0.113.24"))
    }

    @Test func sharedTextSaysWhatFailed() {
        let text = NetworkQualityReport.sample(.partialFailure).sharedText(hidingAddresses: true, timeZone: .gmt)
        #expect(text.contains("上传 未测得"))
        #expect(text.contains("IPv6 当前网络没有 IPv6"))
        #expect(text.contains("归属：查询过于频繁"))
        #expect(text.contains("移动 上海 超时"))
        #expect(text.contains("AbuseIPDB IPv4 查询服务不可用"))
    }

    @Test func webPageChecksNeverClaimMore() {
        #expect(ServiceProbe(name: "GitHub", outcome: .reachable, basis: .webPage).outcomeTitle == "网页可访问")
    }

    @Test func sampleTesterFinishesEveryStep() async {
        var last: NetworkQualityReport?
        for await report in SampleNetworkQualityTester(scenario: .complete, pace: 0.001).run(NetworkQualityStep.allCases, continuing: nil) { last = report }
        #expect(last?.isFinished == true)
        #expect(last?.finishedAt != nil)
        #expect(last?.speed == NetworkQualityReport.sample(.complete).speed)
    }

    @Test func reportsRoundTripThroughJSON() throws {
        let report = NetworkQualityReport.sample(.partialFailure)
        let decoded = try JSONDecoder().decode(NetworkQualityReport.self, from: JSONEncoder().encode(report))
        #expect(decoded == report)
        let bench = DeviceBenchmarkReport.sample()
        #expect(try JSONDecoder().decode(DeviceBenchmarkReport.self, from: JSONEncoder().encode(bench)) == bench)
    }
}
