import Foundation
import Network

public struct NetworkQualityService: Sendable {
    public static let maximumTransferBytes = SpeedTarget.cloudflare.transferSizes.reduce(0, +) * 2

    struct SpeedTarget: Sendable {
        static let cloudflare = Self(
            provider: "Cloudflare",
            latencyURL: URL(string: "https://speed.cloudflare.com/__down?bytes=0")!,
            downloadURL: URL(string: "https://speed.cloudflare.com/__down")!,
            uploadURL: URL(string: "https://speed.cloudflare.com/__up")!,
            transferSizes: [1_000_000, 10_000_000, 10_000_000],
            format: .cloudflare
        )

        enum Format: Sendable { case cloudflare, libreSpeed }

        let provider: String
        let latencyURL: URL
        let downloadURL: URL
        let uploadURL: URL
        let transferSizes: [Int]
        let format: Format

        func downloadURL(bytes: Int) -> URL {
            let size = switch format {
            case .cloudflare: URLQueryItem(name: "bytes", value: String(bytes))
            case .libreSpeed: URLQueryItem(name: "ckSize", value: String(bytes / 1_048_576))
            }
            return downloadURL.appending(queryItems: [size])
        }

        func serverTime(_ response: QualityHTTPResponse) -> TimeInterval {
            format == .cloudflare ? response.serverTime : 0
        }
    }

    private static let attributionURL = URL(string: "https://ipinfo.io")!

    private let request: QualityHTTP.Request?
    private let paths: @Sendable () -> AsyncStream<QualityNetworkPath>
    private let speedTarget: SpeedTarget

    public init() {
        self.init(speedTarget: .cloudflare)
    }

    init(
        request: QualityHTTP.Request? = nil,
        paths: @escaping @Sendable () -> AsyncStream<QualityNetworkPath> = QualityNetworkPath.updates,
        speedTarget: SpeedTarget = .cloudflare
    ) {
        self.request = request
        self.paths = paths
        self.speedTarget = speedTarget
    }

    /// Cancel the calling task to stop the run. The returned report keeps completed checks.
    public func run(
        steps: [NetworkQualityReport.Step] = NetworkQualityReport.Step.allCases,
        onProgress: @escaping @Sendable (NetworkQualityReport) async -> Void = { _ in }
    ) async -> NetworkQualityReport {
        var report = NetworkQualityReport()
        await onProgress(report)
        let updates = paths()
        var iterator = updates.makeAsyncIterator()
        guard let initial = await iterator.next(), !Task.isCancelled else {
            return Self.finish(report, state: Task.isCancelled ? .cancelled : .interrupted(.offline))
        }
        report.network = initial.network
        guard initial.network != .offline else {
            return Self.finish(report, state: .interrupted(.offline))
        }

        let session = request == nil ? QualityHTTP.makeSession() : nil
        defer { session?.invalidateAndCancel() }
        let send: QualityHTTP.Request = request ?? { request, upload in
            guard let session else { throw QualityIssue.invalidResponse }
            let limit = speedTarget.format == .libreSpeed ? Self.responseLimit(for: request, target: speedTarget) : nil
            return try await QualityHTTP.request(using: session, request: request, upload: upload, maximumResponseBytes: limit)
        }
        let startReport = report
        return await withTaskGroup(of: RunEvent.self) { group in
            group.addTask {
                .measured(await Self.measure(startReport, steps: steps, target: speedTarget, send: send, onProgress: onProgress))
            }
            group.addTask {
                if let issue = await QualityNetworkPath.interruption(in: updates, after: initial) {
                    return .interrupted(issue)
                }
                return .monitorEnded
            }
            var completed = startReport
            var interruption: QualityIssue?
            while let event = await group.next() {
                switch event {
                case .measured(let result):
                    completed = result
                    group.cancelAll()
                case .interrupted(let issue):
                    interruption = issue
                    group.cancelAll()
                case .monitorEnded:
                    break
                }
            }
            let state: NetworkQualityReport.State
            if Task.isCancelled { state = .cancelled }
            else if let interruption { state = .interrupted(interruption) }
            else { state = .completed }
            return Self.finish(completed, state: state)
        }
    }

    private enum RunEvent: Sendable {
        case measured(NetworkQualityReport)
        case interrupted(QualityIssue)
        case monitorEnded
    }

    private static func measure(
        _ initial: NetworkQualityReport, steps: [NetworkQualityReport.Step], target: SpeedTarget, send: QualityHTTP.Request,
        onProgress: @Sendable (NetworkQualityReport) async -> Void
    ) async -> NetworkQualityReport {
        var report = initial
        for step in steps {
            switch step {
            case .ipv4:
                await measure(step, at: \.ipv4, report: &report, onProgress: onProgress) { _ in
                    try await publicIP(v6: false, send: send)
                }
            case .ipv6:
                await measure(step, at: \.ipv6, report: &report, onProgress: onProgress) { _ in
                    try await publicIP(v6: true, send: send)
                }
            case .latency:
                await measure(step, at: \.latency, report: &report, onProgress: onProgress) { _ in
                    try await latency(target: target, send: send)
                }
            case .download, .upload:
                let keyPath = step == .upload ? \NetworkQualityReport.upload : \.download
                await measure(step, at: keyPath, report: &report, onProgress: onProgress) { latest in
                    try await bandwidth(upload: step == .upload, target: target, send: send) { sample, fraction in
                        var progress = latest
                        progress.stepFraction = fraction
                        progress.currentMbps = sample.seconds.map { Double(sample.bytes) * 8 / $0 / 1_000_000 }
                        await onProgress(progress)
                    }
                }
            }
        }
        return report
    }

    private static func measure<Value>(
        _ step: NetworkQualityReport.Step,
        at keyPath: WritableKeyPath<NetworkQualityReport, QualityCheck<Value>>,
        report: inout NetworkQualityReport,
        onProgress: @Sendable (NetworkQualityReport) async -> Void,
        operation: (NetworkQualityReport) async throws -> Value
    ) async {
        guard !Task.isCancelled else { return }
        report.currentStep = step
        report[keyPath: keyPath] = .running
        await onProgress(report)
        do {
            try Task.checkCancellation()
            let result = try await operation(report)
            try Task.checkCancellation()
            report[keyPath: keyPath] = .measured(result)
        } catch {
            guard !Task.isCancelled else { return }
            report[keyPath: keyPath] = .unavailable(QualityIssue(error: error))
        }
        report.currentStep = nil
        report.completedStepCount += 1
        await onProgress(report)
    }

    private static func finish(_ initial: NetworkQualityReport, state: NetworkQualityReport.State) -> NetworkQualityReport {
        var report = initial
        if let step = report.currentStep {
            switch step {
            case .ipv4: report.ipv4 = stoppedCheck(state)
            case .ipv6: report.ipv6 = stoppedCheck(state)
            case .latency: report.latency = stoppedCheck(state)
            case .download: report.download = stoppedCheck(state)
            case .upload: report.upload = stoppedCheck(state)
            }
        }
        report.currentStep = nil
        report.state = state
        report.finishedAt = .now
        return report
    }

    private static func stoppedCheck<Value>(_ state: NetworkQualityReport.State) -> QualityCheck<Value> {
        if case .interrupted(let issue) = state { return .unavailable(issue) }
        return .cancelled
    }
}

extension NetworkQualityService {
    private struct IPInfo: Decodable {
        let ip: String
        let country: String?
        let region: String?
        let city: String?
        let org: String?
    }

    private static func publicIP(v6: Bool, send: QualityHTTP.Request) async throws -> QualityPublicIP {
        let url = URL(string: v6 ? "https://api6.ipify.org/" : "https://api.ipify.org/")!
        let checkedAt = Date.now
        let response = try await send(URLRequest(url: url), nil)
        try response.validateStatus()
        let rawAddress = String(decoding: response.body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let address: String
        if v6, let ipv6 = IPv6Address(rawAddress), !ipv6.isIPv4Mapped {
            address = ipv6.debugDescription
        } else if !v6, let ipv4 = IPv4Address(rawAddress) {
            address = ipv4.debugDescription
        } else if IPv4Address(rawAddress) != nil || IPv6Address(rawAddress) != nil {
            throw QualityIssue.wrongAddressFamily
        } else {
            throw QualityIssue.invalidResponse
        }
        let source = QualitySource(provider: "ipify", endpoint: url, checkedAt: checkedAt)
        let attributionSource = QualitySource(provider: "IPinfo", endpoint: attributionURL, checkedAt: .now)
        let attribution: QualityCheck<QualityIPAttribution>
        do {
            try Task.checkCancellation()
            attribution = .measured(try await lookupAttribution(address: address, v6: v6, send: send))
        } catch {
            try Task.checkCancellation()
            attribution = .unavailable(QualityIssue(error: error))
        }
        return QualityPublicIP(address: address, source: source, attributionSource: attributionSource, attribution: attribution)
    }

    static func lookupAttribution(address: String, v6: Bool, send: QualityHTTP.Request) async throws -> QualityIPAttribution {
        try Task.checkCancellation()
        let lookup = try await send(URLRequest(url: attributionURL.appending(path: address).appending(path: "json")), nil)
        try lookup.validateStatus()
        let info = try JSONDecoder().decode(IPInfo.self, from: lookup.body)
        let sameIP = v6 ? IPv6Address(info.ip) == IPv6Address(address) : IPv4Address(info.ip) == IPv4Address(address)
        let network = info.org?.split(separator: " ", maxSplits: 1)
        let asn = network?.first.flatMap { $0.hasPrefix("AS") && Int($0.dropFirst(2)) != nil ? String($0) : nil }
        let networkName = asn == nil ? info.org : network?.dropFirst().first.map(String.init)
        guard sameIP, info.country != nil || networkName != nil || asn != nil else { throw QualityIssue.invalidResponse }
        return QualityIPAttribution(countryCode: info.country, region: info.region, city: info.city, asn: asn, networkName: networkName)
    }

    private static func latency(target: SpeedTarget, send: QualityHTTP.Request) async throws -> QualityLatency {
        let endpoint = target.latencyURL
        let source = QualitySource(provider: target.provider, endpoint: endpoint, checkedAt: .now)
        // Warm up the connection before measuring request-to-first-byte latency.
        if let warmup = try? await send(speedRequest(endpoint, timeout: 4), nil), warmup.statusCode == 429 {
            throw QualityIssue.httpStatus(429)
        }
        var samples: [QualityLatencySample] = []
        for _ in 0..<5 {
            try Task.checkCancellation()
            let started = Date.now
            do {
                let response = try await send(speedRequest(endpoint, timeout: 4), nil)
                try response.validateStatus()
                guard response.body.count <= 1_024, let seconds = response.requestToFirstByte,
                      seconds.isFinite, seconds > 0 else { throw QualityIssue.invalidResponse }
                let adjusted = seconds - target.serverTime(response)
                let latency = (adjusted > 0 ? adjusted : seconds) * 1_000
                samples.append(.init(
                    checkedAt: started, node: response.node, milliseconds: latency, issue: nil,
                    connectionFamily: response.connectionFamily
                ))
            } catch {
                try Task.checkCancellation()
                let issue = QualityIssue(error: error)
                samples.append(.init(checkedAt: started, node: nil, milliseconds: nil, issue: issue))
                if issue == .httpStatus(429) { break }
            }
        }
        let result = QualityLatency(source: source, samples: samples)
        guard result.milliseconds != nil else { throw samples.first?.issue ?? .insufficientSamples }
        return result
    }

    private static func bandwidth(
        upload: Bool, target: SpeedTarget, send: QualityHTTP.Request,
        onSample: (QualityTransferSample, Double) async -> Void
    ) async throws -> QualityBandwidth {
        let endpoint = upload ? target.uploadURL : target.downloadURL
        let source = QualitySource(provider: target.provider, endpoint: endpoint, checkedAt: .now)
        var samples: [QualityTransferSample] = []
        for size in target.transferSizes {
            try Task.checkCancellation()
            let started = Date.now
            let url = upload ? endpoint : target.downloadURL(bytes: size)
            var request = speedRequest(url, timeout: 8)
            do {
                var body: Data?
                if upload {
                    request.httpMethod = "POST"
                    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    body = Data(count: size)
                }
                let response = try await send(request, body)
                try response.validateStatus()
                let measured: TimeInterval?
                if upload { measured = response.requestToFirstByte }
                else { measured = response.requestToEnd.map { $0 - target.serverTime(response) } }
                guard (upload || response.body.count == size), let seconds = measured, seconds.isFinite, seconds > 0 else {
                    throw QualityIssue.invalidResponse
                }
                samples.append(.init(
                    checkedAt: started, node: response.node, bytes: size, seconds: seconds, issue: nil,
                    connectionFamily: response.connectionFamily
                ))
            } catch {
                try Task.checkCancellation()
                let issue = QualityIssue(error: error)
                samples.append(.init(checkedAt: started, node: nil, bytes: size, seconds: nil, issue: issue))
                if issue == .httpStatus(429) { break }
            }
            if let sample = samples.last { await onSample(sample, Double(samples.count) / Double(target.transferSizes.count)) }
        }
        let result = QualityBandwidth(source: source, samples: samples)
        guard result.megabitsPerSecond != nil else {
            throw samples.first?.issue ?? .insufficientSamples
        }
        return result
    }

    private static func responseLimit(for request: URLRequest, target: SpeedTarget) -> Int {
        guard request.httpMethod == "GET", let url = request.url,
              url.path() == target.downloadURL.path(),
              let chunks = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "ckSize" })?.value.flatMap(Int.init),
              (1...4).contains(chunks) else { return 1_024 }
        return chunks * 1_048_576
    }

    private static func speedRequest(_ endpoint: URL, timeout: TimeInterval) -> URLRequest {
        let url = endpoint.appending(queryItems: [URLQueryItem(name: "measId", value: UUID().uuidString)])
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }
}
