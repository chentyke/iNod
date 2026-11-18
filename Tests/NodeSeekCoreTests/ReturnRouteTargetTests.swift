import Testing
@testable import NodeSeekCore

struct ReturnRouteTargetTests {
    @Test func acceptsPublicAddressesTheServiceMeasures() throws {
        #expect(try ReturnRouteTarget.parse(" 1.1.1.1\n").get() == .init(family: .v4, address: "1.1.1.1"))
        #expect(try ReturnRouteTarget.parse("2606:4700:4700::1111").get() == .init(family: .v6, address: "2606:4700:4700::1111"))
        #expect(try ReturnRouteTarget.parse("1。1．1.1").get() == .init(family: .v4, address: "1.1.1.1"))
        #expect(try ReturnRouteTarget.parse("2606：4700::1111").get().address == "2606:4700::1111")
    }

    @Test func explainsAddressesItRejects() {
        #expect(ReturnRouteTarget.parse("   ") == .failure(.empty))
        #expect(ReturnRouteTarget.Problem.empty.message == nil)
        for text in ["example.com", "1.1.1", "1.1.1.1/24", "fe80::1%en0", "256.1.1.1"] {
            #expect(ReturnRouteTarget.parse(text) == .failure(.notAnAddress), "\(text)")
        }
        for text in ["10.0.0.1", "172.20.1.1", "192.168.1.1", "100.64.0.1", "127.0.0.1", "169.254.1.1", "0.1.2.3", "224.0.0.1",
                     "fd00::1", "fe80::1", "::1", "::ffff:1.1.1.1"] {
            #expect(ReturnRouteTarget.parse(text) == .failure(.notPublic), "\(text)")
        }
    }

    @Test func sampleKeepsEachCarrierAndOneFails() {
        let target = ReturnRouteTarget(family: .v6, address: "2001:db8::80")
        let routes = SampleReturnRouteTester.routes(to: target)
        #expect(routes.map(\.carrier) == ChinaCarrier.allCases)
        #expect(routes[0].result.value?.reachedTarget == true)
        #expect(routes[0].result.value?.hops.last?.address == "2001:db8::80")
        #expect(routes[1].result.value?.hops.contains { $0.address == nil } == true)
        #expect(routes[2].result.value == nil)
        #expect(SampleReturnRouteTester.routes(to: target, cancelled: true).allSatisfy { $0.result == .cancelled })
    }

    @Test func lastLatencySkipsSilentHops() {
        let trace = ReturnRoute.Trace(probeCity: "Shanghai", hops: [.init(index: 1, address: "192.0.2.1", rttMs: 4), .init(index: 2, address: nil)],
                                      reachedTarget: false)
        #expect(trace.lastLatencyMs == 4)
    }
}
