import NodeSeekCore
import Network
import Synchronization

struct QualityNetworkPath: Equatable, Sendable {
    let network: NetworkQualityReport.Network
    private let path: NWPath?

    init(network: NetworkQualityReport.Network, path: NWPath? = nil) {
        self.network = network
        self.path = path
    }

    var context: NetworkContext {
        let kind: NetworkKind = switch network {
        case .wifi: .wifi
        case .cellular: .cellular
        case .ethernet: .wired
        case .offline: .offline
        case .unknown, .other: .other
        }
        return NetworkContext(kind: kind, isConstrained: path?.isConstrained ?? false, isExpensive: path?.isExpensive ?? false)
    }

    static func updates() -> AsyncStream<Self> {
        // Keep short-lived changes so a switch followed by an immediate switch back still interrupts the run.
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "iNod.QualityNetworkPath")
            let receivedFirstPath = Mutex(false)
            monitor.pathUpdateHandler = { path in
                receivedFirstPath.withLock { $0 = true }
                let network: NetworkQualityReport.Network
                if path.status != .satisfied { network = .offline }
                else if path.usesInterfaceType(.wifi) { network = .wifi }
                else if path.usesInterfaceType(.cellular) { network = .cellular }
                else if path.usesInterfaceType(.wiredEthernet) { network = .ethernet }
                else { network = .other }
                continuation.yield(Self(network: network, path: path))
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) {
                if !receivedFirstPath.withLock({ $0 }) { continuation.finish() }
            }
        }
    }
}
