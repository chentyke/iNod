import Foundation
import NodeSeekCore
import Synchronization
import Testing
@testable import NodeSeekClient

struct QualityReturnRouteTests {
    @Test func usesRequestedNetworksAndKeepsEachRouteIndependent() async throws {
        let service = QualityReturnRouteService { request, _ in
            if request.httpMethod == "POST" {
                #expect(request.url?.path() == "/v1/measurements")
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(body["target"] as? String == "2001:db8::80")
                let options = try #require(body["measurementOptions"] as? [String: Any])
                #expect(options["ipVersion"] == nil)
                #expect(options["protocol"] as? String == "ICMP")
                let locations = try #require(body["locations"] as? [[String: Any]])
                #expect(locations.compactMap { $0["asn"] as? Int } == [4134, 4837, 9808])
                #expect(locations.allSatisfy { $0["country"] as? String == "CN" && $0["limit"] as? Int == 1 })
                return response(#"{"id":"sample-trace"}"#, status: 202)
            }
            #expect(request.url?.path() == "/v1/measurements/sample-trace")
            return response("""
                {"type":"traceroute","status":"finished","target":"2001:0db8:0:0::80","results":[
                  {"probe":{"asn":4134,"city":"Shanghai","country":"CN"},"result":{"status":"finished","resolvedAddress":"2001:db8::80","hops":[
                    {"resolvedAddress":null,"timings":[]},
                    {"resolvedAddress":"2001:db8::80","timings":[{"rtt":11.0},{"rtt":13.0}]}
                  ]}},
                  {"probe":{"asn":4837,"city":"London","country":"GB"},"result":{"status":"failed"}},
                  {"probe":{"asn":9808,"city":"Taishan","country":"CN"},"result":{"status":"finished","resolvedAddress":"2001:db8::80","hops":[
                    {"resolvedAddress":"2001:db8::9","timings":[{"rtt":30.0}]}
                  ]}}
                ]}
                """)
        }
        let routes = await service.trace(toPublicTarget: target("2001:db8::80", family: .v6))
        #expect(routes.map(\.carrier) == [.telecom, .unicom, .mobile])
        #expect(routes.allSatisfy { $0.family == .v6 })
        let telecom = try #require(routes[0].result.value)
        #expect(telecom.probeCity == "Shanghai")
        #expect(telecom.hops.map(\.index) == [1, 2])
        #expect(telecom.hops[0].address == nil)
        #expect(telecom.hops[1].rttMs == 12)
        #expect(telecom.reachedTarget)
        guard case .unavailable = routes[1].result else { Issue.record("Expected no qualifying Unicom probe"); return }
        let mobile = try #require(routes[2].result.value)
        #expect(!mobile.reachedTarget)
        #expect(mobile.hops.last?.address == "2001:db8::9")
    }

    @Test func keepsFinishedTracesWhenAPollTimesOut() async throws {
        let polled = Mutex(false)
        let service = QualityReturnRouteService { request, _ in
            if request.httpMethod == "POST" { return response(#"{"id":"sample-trace"}"#, status: 202) }
            let wasPolled = polled.withLock { flag in
                let old = flag
                flag = true
                return old
            }
            if wasPolled { throw URLError(.timedOut) }
            return response("""
                {"type":"traceroute","status":"in-progress","target":"192.0.2.80","results":[
                  {"probe":{"asn":4134,"city":"Shanghai","country":"CN"},"result":{
                    "status":"finished","resolvedAddress":"192.0.2.80",
                    "hops":[{"resolvedAddress":"192.0.2.80","timings":[{"rtt":20.0}]}]
                  }},
                  {"probe":{"asn":4837,"city":"Changsha","country":"CN"},"result":{"status":"in-progress"}}
                ]}
                """)
        }
        let routes = await service.trace(toPublicTarget: target("192.0.2.80"))
        #expect(routes[0].result.value?.reachedTarget == true)
        #expect(routes[1].result == .failed(.init(.timedOut)))
        #expect(routes[2].result == .failed(.init(.timedOut)))
    }

    @Test func refusesToSubmitPrivateAddresses() async {
        let service = QualityReturnRouteService { _, _ in
            Issue.record("Private address submitted to a public service")
            throw URLError(.badURL)
        }
        let ipv4 = await service.trace(toPublicTarget: target("10.0.0.1"))
        let ipv6 = await service.trace(toPublicTarget: target("fd00::1", family: .v6))
        #expect(ipv4.count == 3)
        #expect(ipv6.count == 3)
        for route in ipv4 + ipv6 {
            #expect(route.result == .unavailable(.init(.notSupported, detail: "需要可公开探测的公网地址")))
        }
    }

    @Test func liveTesterCarriesTheTargetIntoEachRoute() async {
        let tester = LiveReturnRouteTester(service: QualityReturnRouteService { request, _ in
            if request.httpMethod == "POST" { return response(#"{"id":"sample-trace"}"#, status: 202) }
            return response("""
                {"type":"traceroute","status":"finished","target":"192.0.2.80","results":[
                  {"probe":{"asn":4837,"city":"Beijing","country":"CN"},"result":{
                    "status":"finished","resolvedAddress":"192.0.2.80",
                    "hops":[{"resolvedAddress":null,"timings":[]},{"resolvedAddress":"192.0.2.80","timings":[{"rtt":40.0}]}]
                  }}
                ]}
                """)
        })
        let target = ReturnRouteTarget(family: .v4, address: "192.0.2.80")
        let routes = await tester.trace(to: target)
        #expect(routes.map(\.carrier) == [.telecom, .unicom, .mobile])
        #expect(routes.allSatisfy { $0.target == target })
        #expect(routes[1].result.value == .init(probeCity: "Beijing", hops: [.init(index: 1, address: nil), .init(index: 2, address: "192.0.2.80", rttMs: 40)],
                                                reachedTarget: true))
        #expect(routes[1].result.value?.lastLatencyMs == 40)
        guard case .unavailable = routes[0].result else { Issue.record("Expected no Telecom probe"); return }
    }

    private func target(_ address: String, family: IPFamily = .v4) -> IPEgress {
        .init(family: family, address: address, echoSource: "Example", owner: nil, queriedAt: .now)
    }
}

private func response(_ json: String, status: Int = 200) -> QualityHTTPResponse {
    .init(body: Data(json.utf8), statusCode: status)
}
