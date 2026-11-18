import Foundation
import NodeSeekCore

/// `QualityReturnRouteService` behind the UI's `ReturnRouteTesting` contract. Each call publishes `target`
/// through Globalping, so call it only after the reader agreed to that.
public struct LiveReturnRouteTester: ReturnRouteTesting {
    private let service: QualityReturnRouteService

    public init() { self.init(service: QualityReturnRouteService()) }
    init(service: QualityReturnRouteService) { self.service = service }

    public func trace(to target: ReturnRouteTarget) async -> [ReturnRoute] {
        let egress = IPEgress(family: target.family, address: target.address, echoSource: "", owner: nil, queriedAt: .now)
        return await service.trace(toPublicTarget: egress).map { route in
            let result: QualityResult<ReturnRoute.Trace> = switch route.result {
            case .measured(let trace): .measured(.init(probeCity: trace.probeCity, hops: trace.hops, reachedTarget: trace.reachedTarget))
            case .pending: .pending
            case .running(let progress): .running(progress)
            case .failed(let issue): .failed(issue)
            case .unavailable(let issue): .unavailable(issue)
            case .cancelled: .cancelled
            case .notIncluded: .notIncluded
            }
            return ReturnRoute(carrier: route.carrier, probeASN: route.probeASN, target: target, startedAt: route.startedAt, result: result)
        }
    }
}
