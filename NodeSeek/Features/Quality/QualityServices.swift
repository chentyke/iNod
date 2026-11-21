import Foundation
import Network
import NodeSeekClient
import NodeSeekCore
import SwiftUI

enum QualityServices {
    static var usesSamples: Bool {
        #if DEBUG
        UITestNetwork.isActive
        #else
        ProcessInfo.processInfo.arguments.contains("--ui-test-offline")
        #endif
    }

    static var network: any NetworkQualityTesting {
        guard usesSamples else { return LiveNetworkQualityTester() }
        let defaults = UserDefaults.standard
        let scenario = defaults.string(forKey: "qualitySample").flatMap(QualitySampleScenario.init) ?? .complete
        return SampleNetworkQualityTester(scenario: scenario, pace: pace)
    }

    static var device: any DeviceBenchmarking {
        if usesSamples { return SampleDeviceBenchmark(pace: pace) }
        return LiveDeviceBenchmark()
    }

    /// Launch arguments arrive as strings; `double(forKey:)` parses them.
    static var pace: Double {
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
        if QualityServices.usesSamples {
            context = .init(kind: .wifi)
            return
        }
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
        return .init(kind: kind, isConstrained: path.isConstrained, isExpensive: path.isExpensive)
    }
}
