import Foundation
import Network
import NodeSeekCore
import SwiftUI

/// The detection services the quality screens run. Until the real services land, both play back sample data;
/// `-qualitySample <complete|partialFailure|offline>` and `-qualityPace <seconds factor>` pick which and how fast.
enum QualityServices {
    static var network: any NetworkQualityTesting {
        let defaults = UserDefaults.standard
        let scenario = defaults.string(forKey: "qualitySample").flatMap(QualitySampleScenario.init) ?? .complete
        return SampleNetworkQualityTester(scenario: scenario, pace: pace)
    }
    static var device: any DeviceBenchmarking { SampleDeviceBenchmark(pace: pace) }

    /// Launch arguments arrive as strings; `double(forKey:)` parses them.
    private static var pace: Double {
        let pace = UserDefaults.standard.double(forKey: "qualityPace")
        return pace > 0 ? pace : 1
    }
}

/// The connection the phone would test on right now, shown before a run starts.
@MainActor @Observable
final class CurrentNetworkMonitor {
    private(set) var context = NetworkContext(kind: .other)
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let context = Self.context(for: path)
            Task { @MainActor in self?.context = context }
        }
        monitor.start(queue: DispatchQueue(label: "quality.path"))
    }
    deinit { monitor.cancel() }

    nonisolated private static func context(for path: NWPath) -> NetworkContext {
        guard path.status == .satisfied else { return .init(kind: .offline) }
        let kind: NetworkKind = path.usesInterfaceType(.wifi) ? .wifi
            : path.usesInterfaceType(.cellular) ? .cellular
            : path.usesInterfaceType(.wiredEthernet) ? .wired : .other
        // A VPN shows up as an extra "other" interface alongside the physical one.
        let vpn = kind != .other && path.availableInterfaces.contains { $0.type == .other }
        return .init(kind: kind, isConstrained: path.isConstrained, isExpensive: path.isExpensive, usesVPN: vpn)
    }
}
