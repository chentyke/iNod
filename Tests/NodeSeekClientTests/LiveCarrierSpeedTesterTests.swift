import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

struct LiveCarrierSpeedTesterTests {
    @Test func mapsTheNodeAndKeepsDirectionFailures() async throws {
        let tester = LiveCarrierSpeedTester(service: service(uploadStatus: 503), nodes: [node])
        let listed = try #require(tester.nodes.first)
        #expect(listed.provider == "LibreSpeed")
        #expect(listed.city == "测试城市")
        #expect(listed.carrier == .unicom)
        #expect(listed.host == "speed.example.org")
        #expect(listed.maximumBytes == Int64(QualityCarrierSpeedService.maximumTransferBytesPerNode))

        var snapshots: [CarrierSpeedReport] = []
        for await report in tester.run(listed) { snapshots.append(report) }
        #expect(snapshots.contains { if case .running(let progress) = $0.speed { progress.stage == .download } else { false } })
        let last = try #require(snapshots.last)
        #expect(last.finishedAt != nil)
        #expect(last.network.kind == .wifi)
        let speed = try #require(last.speed.value)
        #expect(speed.server.provider == "LibreSpeed")
        #expect(speed.server.location == "测试城市联通")
        #expect(speed.latencyMs == 50)
        #expect(speed.latencySamples == 5)
        #expect(speed.downloadMbps == 67.108864)
        #expect(speed.uploadMbps == nil)
        #expect(speed.issues.first?.detail == "上传未测得，HTTP 503")
        #expect(speed.bytesTransferred == 9 * 1_048_576)
    }

    @Test func aRunWithNoResultFails() async throws {
        let tester = LiveCarrierSpeedTester(service: QualityCarrierSpeedService(request: { _, _ in .init(statusCode: 503) }, paths: {
            AsyncStream { $0.yield(.init(network: .wifi)) }
        }), nodes: [node])
        var last: CarrierSpeedReport?
        for await report in tester.run(try #require(tester.nodes.first)) { last = report }
        #expect(last?.speed.status == .failed(.init(.serviceUnavailable, detail: "HTTP 503")))
    }

    @Test func anUnknownNodeFailsWithoutRequests() async {
        let tester = LiveCarrierSpeedTester(service: QualityCarrierSpeedService(request: { _, _ in
            Issue.record("An unknown node should not send requests")
            throw URLError(.badURL)
        }, paths: { AsyncStream { $0.yield(.init(network: .wifi)) } }), nodes: [node])
        var last: CarrierSpeedReport?
        for await report in tester.run(.sample) { last = report }
        if case .failed = last?.speed {} else { Issue.record("Expected a failure, got \(String(describing: last?.speed))") }
    }

    private let node = QualityCarrierSpeedNode(
        carrier: .unicom, city: "测试城市", latencyURL: URL(string: "https://speed.example.org/latency")!,
        downloadURL: URL(string: "https://speed.example.org/download")!, uploadURL: URL(string: "https://speed.example.org/upload")!
    )

    private func service(uploadStatus: Int) -> QualityCarrierSpeedService {
        QualityCarrierSpeedService(request: { request, _ in
            let url = try #require(request.url)
            if request.httpMethod == "POST" { return .init(statusCode: uploadStatus) }
            if url.path() == "/latency" { return .init(requestToFirstByte: 0.05, serverTime: 0.04, connectionFamily: .ipv4) }
            let chunks = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ckSize" })?.value.flatMap(Int.init) ?? 1
            return .init(body: Data(count: chunks * 1_048_576), requestToEnd: 0.5, serverTime: 0.2, connectionFamily: .ipv4)
        }, paths: { AsyncStream { $0.yield(.init(network: .wifi)) } })
    }
}
