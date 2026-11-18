import Foundation

/// Where one measurement stands. The detection service fills these in; the UI draws whatever it holds.
public enum QualityResult<Value: Sendable & Equatable & Codable>: Sendable, Equatable, Codable {
    /// Waiting for an earlier step.
    case pending
    case running(QualityProgress)
    case measured(Value)
    /// The test ran and went wrong (timeout, the network dropped, a service errored).
    case failed(QualityIssue)
    /// The test could not run here at all, such as IPv6 on a network without it.
    case unavailable(QualityIssue)
    case cancelled
    /// Left out of this run's scope.
    case notIncluded

    public var value: Value? { if case .measured(let value) = self { value } else { nil } }
    public var status: QualityStatus {
        switch self {
        case .pending: .pending
        case .running(let progress): .running(progress)
        case .measured: .measured
        case .failed(let issue): .failed(issue)
        case .unavailable(let issue): .unavailable(issue)
        case .cancelled: .cancelled
        case .notIncluded: .notIncluded
        }
    }
    public var isMeasured: Bool { value != nil }
    public func map<T>(_ transform: (Value) -> T) -> QualityResult<T> {
        switch self {
        case .pending: .pending
        case .running(let progress): .running(progress)
        case .measured(let value): .measured(transform(value))
        case .failed(let issue): .failed(issue)
        case .unavailable(let issue): .unavailable(issue)
        case .cancelled: .cancelled
        case .notIncluded: .notIncluded
        }
    }
    /// A step that has not finished turns into `.cancelled`; finished results stay as they are.
    public var cancellingUnfinished: Self {
        switch self { case .pending, .running: .cancelled; default: self }
    }
}

/// `QualityResult` without its value, for lists of steps.
public enum QualityStatus: Sendable, Equatable {
    case pending, running(QualityProgress), measured, failed(QualityIssue), unavailable(QualityIssue), cancelled, notIncluded

    public var isFinished: Bool {
        switch self { case .pending, .running: false; default: true }
    }
    /// Steps the reader can run again from the report.
    public var canRetry: Bool {
        switch self { case .failed, .cancelled: true; default: false }
    }
}

public struct QualityProgress: Sendable, Equatable, Codable {
    /// 0...1, or nil while the service can't tell.
    public var fraction: Double?
    public var stage: QualityStage?
    /// The speed this instant, for the live readout during download and upload.
    public var currentMbps: Double?

    public init(fraction: Double? = nil, stage: QualityStage? = nil, currentMbps: Double? = nil) {
        self.fraction = fraction; self.stage = stage; self.currentMbps = currentMbps
    }
}

/// Parts of a step the UI names while it runs. The UI owns the wording.
public enum QualityStage: String, Sendable, Codable {
    case findingServer, latency, download, upload, lookingUpOwner, tracing, querying
}

public struct QualityIssue: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case timedOut, offline, networkChanged, serviceUnavailable, noIPv4, noIPv6, notSupported, refused, rateLimited, other
    }
    public var kind: Kind
    /// Extra detail from the service, shown under the UI's own sentence.
    public var detail: String?

    public init(_ kind: Kind, detail: String? = nil) { self.kind = kind; self.detail = detail }
}

public enum IPFamily: String, Sendable, Codable, CaseIterable { case v4, v6 }

public enum NetworkKind: String, Sendable, Codable { case wifi, cellular, wired, other, offline }

/// The network a run went out on.
public struct NetworkContext: Sendable, Equatable, Codable {
    public var kind: NetworkKind
    /// Low Data Mode or a metered connection.
    public var isConstrained: Bool
    public var isExpensive: Bool
    /// True when the system reports a VPN or a proxy carrying the traffic.
    public var usesVPN: Bool

    public init(kind: NetworkKind, isConstrained: Bool = false, isExpensive: Bool = false, usesVPN: Bool = false) {
        self.kind = kind; self.isConstrained = isConstrained; self.isExpensive = isExpensive; self.usesVPN = usesVPN
    }
}
