import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

struct QualityCarrierSpeedTests {
    @Test func measuresTheConfiguredNodeAndKeepsDirectionFailuresSeparate() async throws {
        let service = QualityCarrierSpeedService(request: { request, upload in
            let url = try #require(request.url)
            #expect(url.host() == "speed.example.org")
            if request.httpMethod == "POST" {
                #expect(url.path() == "/upload")
                #expect([1_048_576, 4_194_304].contains(upload?.count ?? 0))
                return .init(statusCode: 503)
            }
            if url.path() == "/latency" {
                return .init(requestToFirstByte: 0.05, serverTime: 0.04, connectionFamily: .ipv4)
            }
            #expect(url.path() == "/download")
            let count = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ckSize" })?.value.flatMap(Int.init)
            let chunks = try #require(count)
            #expect([1, 4].contains(chunks))
            return .init(body: Data(count: chunks * 1_048_576), requestToEnd: 0.5,
                         serverTime: 0.2, connectionFamily: .ipv4)
        }, paths: {
            AsyncStream { $0.yield(.init(network: .wifi)) }
        })

        let result = try await service.run(at: node())
        #expect(result.node.carrier == .unicom)
        #expect(result.node.city == "测试城市")
        #expect(result.report.network == .wifi)
        #expect(result.report.latency.value?.milliseconds == 50)
        #expect(result.report.latency.value?.samples.count == 5)
        #expect(result.report.download.value?.samples.map(\.bytes) == [1_048_576, 4_194_304, 4_194_304])
        #expect(result.report.download.value?.megabitsPerSecond == 67.108864)
        #expect(result.report.download.value?.samples.first?.connectionFamily == .ipv4)
        #expect(result.report.download.value?.source.provider == "LibreSpeed")
        #expect(result.report.upload == .unavailable(.httpStatus(503)))
        #expect(QualityCarrierSpeedService.maximumTransferBytesPerNode == 18 * 1_048_576)
    }

    @Test func verifiesThePublicNodesProtocolAndUploadAcknowledgement() async throws {
        let node = QualityCarrierSpeedNode.taiyuanUnicom
        let service = QualityCarrierSpeedService(request: { request, upload in
            let url = try #require(request.url)
            #expect(url.host() == node.downloadURL.host())
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(query.contains(where: { $0.name == "r" }))
            switch url.path() {
            case "/hello":
                return .init(body: Data("hello v3.5.5".utf8), requestToFirstByte: 0.08)
            case "/download":
                #expect(query.contains(where: { $0.name == "size" && $0.value == "10485760" }))
                return .init(body: Data(count: 10 * 1_048_576), requestToEnd: 2)
            case "/upload":
                #expect(request.httpMethod == "POST")
                #expect(upload?.count == 4 * 1_048_576)
                // The endpoint acknowledges a smaller amount than the client sent.
                return .init(body: Data("upload size:65536".utf8), requestToFirstByte: 0.5)
            default:
                throw URLError(.badURL)
            }
        }, paths: {
            AsyncStream { $0.yield(.init(network: .wifi)) }
        })
        let result = try await service.run(at: node)
        #expect(result.node.carrier == .unicom)
        #expect(result.report.latency.value?.milliseconds == 80)
        #expect(result.report.download.value?.megabitsPerSecond == 41.94304)
        #expect(result.report.upload == .unavailable(.invalidResponse))
    }

    @Test func rejectsMixedOriginsBeforeSendingRequests() async {
        let service = QualityCarrierSpeedService(request: { _, _ in
            Issue.record("Invalid server configuration should not send requests")
            throw URLError(.badURL)
        }, paths: { AsyncStream { $0.yield(.init(network: .wifi)) } })
        await #expect(throws: QualityIssue.invalidResponse) {
            try await service.run(at: node(uploadHost: "other.example.org"))
        }
    }

    private func node(uploadHost: String = "speed.example.org") -> QualityCarrierSpeedNode {
        .init(
            carrier: .unicom, city: "测试城市", latencyURL: URL(string: "https://speed.example.org/latency")!,
            downloadURL: URL(string: "https://speed.example.org/download")!,
            uploadURL: URL(string: "https://\(uploadHost)/upload")!
        )
    }
}
