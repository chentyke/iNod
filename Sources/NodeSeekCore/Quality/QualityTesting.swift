import Foundation

/// The network detection service, as the UI calls it.
///
/// `run` yields a full report snapshot after every change and finishes once every included step has finished.
/// The UI stops a run by cancelling the task that iterates the stream; it then marks unfinished steps cancelled itself
/// (`cancellingUnfinished`), so the service only has to stop its requests.
public protocol NetworkQualityTesting: Sendable {
    /// Rough mobile data one full run uses, shown before the reader starts.
    var estimatedUsage: ClosedRange<Int64> { get }
    /// Steps this build can measure. Anything else is reported as `.notIncluded`.
    var supportedSteps: [NetworkQualityStep] { get }
    /// Runs `steps`. With `previous`, results for other steps carry over unchanged (used by retry).
    func run(_ steps: [NetworkQualityStep], continuing previous: NetworkQualityReport?) -> AsyncStream<NetworkQualityReport>
}

/// The on-device benchmark, as the UI calls it. Same contract as `NetworkQualityTesting`.
public protocol DeviceBenchmarking: Sendable {
    /// Temporary file space the storage test needs; it is deleted when the run ends.
    var scratchBytes: Int64 { get }
    func run() -> AsyncStream<DeviceBenchmarkReport>
}
