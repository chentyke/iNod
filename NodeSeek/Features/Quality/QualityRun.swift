import Foundation
import NodeSeekCore
import SwiftUI

/// Drives one network check screen: start, cancel, retry, and the latest report.
@MainActor @Observable
final class NetworkQualityRun {
    private(set) var report: NetworkQualityReport?
    private(set) var isRunning = false
    @ObservationIgnored private nonisolated(unsafe) var task: Task<Void, Never>?
    @ObservationIgnored let tester: any NetworkQualityTesting

    init(tester: any NetworkQualityTesting = QualityServices.network, report: NetworkQualityReport? = nil) {
        self.tester = tester; self.report = report
    }
    deinit { task?.cancel() }

    var retryableSteps: [NetworkQualityStep] {
        guard let report, !isRunning else { return [] }
        return report.retryableSteps
    }

    func start() { run(tester.supportedSteps, continuing: nil) }
    func retry(_ steps: [NetworkQualityStep]) { run(steps, continuing: report) }

    func cancel() {
        task?.cancel(); task = nil
        if let report, !report.isFinished || report.finishedAt == nil { self.report = report.cancellingUnfinished() }
        isRunning = false
    }

    private func run(_ steps: [NetworkQualityStep], continuing previous: NetworkQualityReport?) {
        task?.cancel()
        isRunning = true
        let stream = tester.run(steps, continuing: previous)
        task = Task { [weak self] in
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { return }
                self.report = snapshot
            }
            guard let self, !Task.isCancelled else { return }
            // A stream that ends early leaves steps unfinished; treat them like a cancel so nothing spins forever.
            if let report = self.report, !report.isFinished { self.report = report.cancellingUnfinished() }
            self.isRunning = false
        }
    }
}

@MainActor @Observable
final class DeviceBenchmarkRun {
    private(set) var report: DeviceBenchmarkReport?
    private(set) var isRunning = false
    private(set) var history: [DeviceBenchmarkReport]
    @ObservationIgnored private nonisolated(unsafe) var task: Task<Void, Never>?
    @ObservationIgnored let benchmark: any DeviceBenchmarking
    @ObservationIgnored private let store: UserDefaults
    private static let historyKey = "quality.benchmarkHistory"
    private static let historyLimit = 20

    init(benchmark: any DeviceBenchmarking = QualityServices.device, store: UserDefaults = .standard) {
        self.benchmark = benchmark; self.store = store
        history = (store.data(forKey: Self.historyKey)).flatMap { try? JSONDecoder().decode([DeviceBenchmarkReport].self, from: $0) } ?? []
    }
    deinit { task?.cancel() }

    func start() {
        task?.cancel()
        isRunning = true
        let stream = benchmark.run()
        task = Task { [weak self] in
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { return }
                self.report = snapshot
            }
            guard let self, !Task.isCancelled else { return }
            if let report = self.report {
                if report.isComplete { self.remember(report) } else if !report.isFinished { self.report = report.cancellingUnfinished() }
            }
            self.isRunning = false
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        report = report?.cancellingUnfinished()
        isRunning = false
    }

    func forget(_ report: DeviceBenchmarkReport) {
        history.removeAll { $0.id == report.id }
        save()
    }

    private func remember(_ report: DeviceBenchmarkReport) {
        history.insert(report, at: 0)
        history = Array(history.prefix(Self.historyLimit))
        save()
    }
    private func save() { store.set(try? JSONEncoder().encode(history), forKey: Self.historyKey) }
}
