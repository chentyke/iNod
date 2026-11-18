import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

struct QualityIPDetailsTests {
    @Test func keepsRoutingAndRiskSeparateForBothMeasuredAddresses() async throws {
        let service = QualityIPDetailsService { request, upload in
            #expect(upload == nil)
            let url = try #require(request.url)
            switch url.host() {
            case "stat.ripe.net":
                let resource = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "resource" })?.value
                switch resource {
                case "192.0.2.80":
                    return response(#"{"status":"ok","data":{"asns":["64497","64496","64497"],"prefix":"192.0.2.0/24"}}"#)
                case "2001:db8:2::1":
                    throw URLError(.timedOut)
                default:
                    throw URLError(.badURL)
                }
            case "api.ipquery.io":
                switch url.lastPathComponent {
                case "192.0.2.80":
                    return .init(statusCode: 429)
                case "2001:db8:2::1":
                    return response(#"{"ip":"2001:0db8:0002::1","risk":{"risk_score":0,"is_vpn":false,"is_datacenter":true}}"#)
                default:
                    throw URLError(.badURL)
                }
            default:
                throw URLError(.badURL)
            }
        }
        let details = await service.run(for: report())
        #expect(details.map(\.family) == [.v4, .v6])
        let ipv4 = try #require(details.first)
        let ipv6 = try #require(details.last)
        #expect(ipv4.routing.provider == "RIPEstat")
        #expect(ipv4.routing.result.value == .announced(prefix: "192.0.2.0/24", originASNs: [64496, 64497]))
        #expect(ipv4.risk.result == .failed(.init(.rateLimited)))
        #expect(ipv6.routing.result == .failed(.init(.timedOut)))
        #expect(ipv6.risk.provider == "IPQuery")
        let risk = try #require(ipv6.risk.result.value)
        #expect(risk.score == 0)
        #expect(risk.isVPN == false)
        #expect(risk.isDatacenter == true)
        #expect(risk.isProxy == nil)
        #expect(try JSONDecoder().decode([QualityIPDetails].self, from: JSONEncoder().encode(details)) == details)
    }

    @Test func distinguishesNoObservedAnnouncementFromInvalidData() async throws {
        let service = QualityIPDetailsService { request, _ in
            if request.url?.host() == "api.ipquery.io" {
                return response(#"{"ip":"192.0.2.81","risk":{"risk_score":30}}"#)
            }
            if request.url?.query()?.contains("192.0.2.80") == true {
                return response(#"{"status":"ok","data":{"asns":[],"prefix":""}}"#)
            }
            return response(#"{"status":"ok","data":{"asns":["64496"],"prefix":"2001:db8:7::/48"}}"#)
        }
        let details = await service.run(for: report())
        let ipv4 = try #require(details.first)
        let ipv6 = try #require(details.last)
        #expect(ipv4.routing.result.value == .noAnnouncementObserved)
        #expect(ipv6.routing.result == .failed(.init(.serviceUnavailable)))
        #expect(details.allSatisfy { $0.risk.result == .failed(.init(.serviceUnavailable)) })
    }

    @Test func doesNotQueryAnAddressThatWasNotMeasured() async throws {
        var base = report()
        base.ipv6 = .failed(.init(.timedOut))
        let service = QualityIPDetailsService { request, _ in
            if request.url?.host() == "api.ipquery.io" {
                #expect(request.url?.lastPathComponent == "192.0.2.80")
                return response(#"{"ip":"192.0.2.80","risk":{"is_mobile":true}}"#)
            }
            #expect(request.url?.query()?.contains("192.0.2.80") == true)
            return response(#"{"status":"ok","data":{"asns":["64496"],"prefix":"192.0.2.0/24"}}"#)
        }
        let details = await service.run(for: base)
        #expect(details.map(\.family) == [.v4])
        let risk = try #require(details.first?.risk.result.value)
        #expect(risk.score == nil)
        #expect(risk.isMobile == true)
    }

    private func report() -> NodeSeekCore.NetworkQualityReport {
        .init(
            startedAt: .now, network: .init(kind: .wifi),
            ipv4: .measured(.init(family: .v4, address: "192.0.2.80", echoSource: "Example", owner: nil, queriedAt: .now)),
            ipv6: .measured(.init(family: .v6, address: "2001:db8:2::1", echoSource: "Example", owner: nil, queriedAt: .now))
        )
    }
}

private func response(_ json: String) -> QualityHTTPResponse {
    .init(body: Data(json.utf8))
}
