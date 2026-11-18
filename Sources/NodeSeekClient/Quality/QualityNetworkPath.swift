import NodeSeekCore
import Network
import Synchronization

struct QualityNetworkPath: Sendable {
    let network: NetworkQualityReport.Network
    private var interfaces: Set<String>
    private var gateways: Set<NWEndpoint>
    private let isConstrained: Bool
    private let isExpensive: Bool

    init(
        network: NetworkQualityReport.Network, interfaces: Set<String> = [], gateways: Set<NWEndpoint> = [],
        isConstrained: Bool = false, isExpensive: Bool = false
    ) {
        self.network = network
        self.interfaces = interfaces
        self.gateways = gateways
        self.isConstrained = isConstrained
        self.isExpensive = isExpensive
    }

    var context: NetworkContext {
        let kind: NetworkKind = switch network {
        case .wifi: .wifi
        case .cellular: .cellular
        case .ethernet: .wired
        case .offline: .offline
        case .unknown, .other: .other
        }
        return NetworkContext(kind: kind, isConstrained: isConstrained, isExpensive: isExpensive)
    }

    static func interruption(in updates: AsyncStream<Self>, after initial: Self) async -> QualityIssue? {
        var lastKnown = initial
        for await path in updates {
            if path.network == .offline { return .offline }
            if path.network != lastKnown.network ||
                areBothKnownAndDisjoint(path.interfaces, lastKnown.interfaces) ||
                areBothKnownAndDisjoint(path.gateways, lastKnown.gateways) {
                return .networkChanged
            }
            // A path can gain details as the system evaluates it. Preserve the last route information
            // when an update omits it, and do not treat changes to DNS or data-mode flags as a switch.
            if !path.interfaces.isEmpty { lastKnown.interfaces = path.interfaces }
            if !path.gateways.isEmpty { lastKnown.gateways = path.gateways }
        }
        return nil
    }

    private static func areBothKnownAndDisjoint<Value>(_ lhs: Set<Value>, _ rhs: Set<Value>) -> Bool {
        !lhs.isEmpty && !rhs.isEmpty && lhs.isDisjoint(with: rhs)
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
                let interfaces = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }.map(\.name)
                continuation.yield(Self(
                    network: network, interfaces: Set(interfaces), gateways: Set(path.gateways),
                    isConstrained: path.isConstrained, isExpensive: path.isExpensive
                ))
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) {
                if !receivedFirstPath.withLock({ $0 }) { continuation.finish() }
            }
        }
    }
}
