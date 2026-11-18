import Foundation
import NodeSeekCore
import Testing

struct CarrierSpeedReportTests {
    @Test func sampleTesterEndsWithTheSampleResult() async {
        var snapshots: [CarrierSpeedReport] = []
        for await report in SampleCarrierSpeedTester(scenario: .complete, pace: 0.001).run(.sample) { snapshots.append(report) }
        #expect(snapshots.first?.speed == .pending)
        #expect(snapshots.contains { if case .running(let progress) = $0.speed { progress.stage == .upload } else { false } })
        let last = snapshots.last
        #expect(last?.isFinished == true)
        #expect(last?.speed.value?.downloadMbps == 312.4)
        #expect(last?.speed.value?.server.location == "太原联通")
    }

    @Test func offlineSampleFails() async {
        var last: CarrierSpeedReport?
        for await report in SampleCarrierSpeedTester(scenario: .offline, pace: 0.001).run(.sample) { last = report }
        #expect(last?.speed == .failed(.init(.offline)))
    }

    @Test func cancellingKeepsMeasuredDirections() {
        var report = CarrierSpeedReport(node: .sample, startedAt: .now, network: .init(kind: .wifi))
        report.speed = .running(.init(fraction: 0.7, stage: .upload))
        report.partialSpeed = .init(server: .init(provider: "SpeedTest.cn", location: "太原联通"), downloadMbps: 90, uploadMbps: nil,
                                    latencyMs: 40, jitterMs: 2, latencySamples: 5, bytesTransferred: 10_485_760)
        let cancelled = report.cancellingUnfinished()
        #expect(cancelled.speed.value?.downloadMbps == 90)
        #expect(cancelled.speed.value?.issues == [CarrierSpeedReport.cancelledIssue])
        #expect(cancelled.partialSpeed == nil)
        #expect(cancelled.finishedAt != nil)

        report.partialSpeed = nil
        #expect(report.cancellingUnfinished().speed == .cancelled)
    }

    @Test func finishedResultsSurviveCancelling() {
        let report = CarrierSpeedReport.sample(.partialFailure)
        #expect(report.cancellingUnfinished() == report)
    }
}
