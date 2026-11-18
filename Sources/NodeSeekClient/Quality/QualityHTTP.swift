import Foundation
import Network
import Synchronization

struct QualityHTTPResponse: Sendable {
    let body: Data
    let statusCode: Int
    let node: String?
    let requestToFirstByte: TimeInterval?
    let requestToEnd: TimeInterval?
    let serverTime: TimeInterval
    let connectionFamily: QualityIPFamily?

    init(
        body: Data = Data(), statusCode: Int = 200, node: String? = nil,
        requestToFirstByte: TimeInterval? = nil, requestToEnd: TimeInterval? = nil,
        serverTime: TimeInterval = 0, connectionFamily: QualityIPFamily? = nil
    ) {
        self.body = body
        self.statusCode = statusCode
        self.node = node
        self.requestToFirstByte = requestToFirstByte
        self.requestToEnd = requestToEnd
        self.serverTime = serverTime
        self.connectionFamily = connectionFamily
    }

    func validateStatus() throws {
        guard (200..<300).contains(statusCode) else { throw QualityIssue.httpStatus(statusCode) }
    }
}

extension QualityIssue {
    init(error: any Error) {
        switch error {
        case let issue as QualityIssue: self = issue
        case let error as URLError:
            switch error.code {
            case .timedOut: self = .timedOut
            case .notConnectedToInternet: self = .offline
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost: self = .hostUnreachable
            default: self = .transportError(error.errorCode)
            }
        default: self = .invalidResponse
        }
    }
}

struct QualityHTTP {
    typealias Request = @Sendable (URLRequest, Data?) async throws -> QualityHTTPResponse

    static func makeSession(resourceTimeout: TimeInterval = 12) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }

    static func request(
        using session: URLSession, request: URLRequest, upload: Data?, maximumResponseBytes: Int? = nil
    ) async throws -> QualityHTTPResponse {
        let capture = MetricsCapture(maximumResponseBytes: maximumResponseBytes)
        let (data, response): (Data, URLResponse)
        if let limit = maximumResponseBytes, upload != nil {
            var request = request
            request.httpBody = upload
            let (bytes, reply) = try await session.bytes(for: request, delegate: capture)
            var body = Data()
            for try await byte in bytes {
                guard body.count < limit else { throw QualityIssue.invalidResponse }
                body.append(byte)
            }
            (data, response) = (body, reply)
        } else if let upload {
            (data, response) = try await session.upload(for: request, from: upload, delegate: capture)
        } else if let limit = maximumResponseBytes {
            do {
                let (file, reply) = try await session.download(for: request, delegate: capture)
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard let size, size <= limit else { throw QualityIssue.invalidResponse }
                (data, response) = (try Data(contentsOf: file), reply)
            } catch {
                if capture.exceededMaximum.withLock({ $0 }) { throw QualityIssue.invalidResponse }
                throw error
            }
        } else {
            (data, response) = try await session.data(for: request, delegate: capture)
        }
        guard let http = response as? HTTPURLResponse else { throw QualityIssue.invalidResponse }
        let metrics = capture.timing.withLock { $0 }
        let ray = http.value(forHTTPHeaderField: "CF-Ray")
        let node = ray.flatMap { value -> String? in
            guard let suffix = value.split(separator: "-").last, suffix.count == 3 else { return nil }
            return String(suffix)
        }
        let header = http.value(forHTTPHeaderField: "Server-Timing") ?? ""
        let timings = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let worker = serverTiming("cfSpeedWorker", in: timings)
        let edge = serverTiming("cfSpeedEdge", in: timings)
        return QualityHTTPResponse(
            body: data, statusCode: http.statusCode, node: node, requestToFirstByte: metrics?.firstByte,
            requestToEnd: metrics?.end, serverTime: (worker ?? edge ?? 0) / 1_000, connectionFamily: metrics?.family
        )
    }

    private static func serverTiming(_ name: String, in timings: [String]) -> Double? {
        timings.first { $0.hasPrefix("\(name);") }?
            .split(separator: ";")
            .first { $0.hasPrefix("dur=") }
            .flatMap { Double($0.dropFirst(4)) }
            .flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private final class MetricsCapture: NSObject, URLSessionDownloadDelegate {
        private let maximumResponseBytes: Int?
        let exceededMaximum = Mutex(false)

        init(maximumResponseBytes: Int?) {
            self.maximumResponseBytes = maximumResponseBytes
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
        ) {
            guard let maximumResponseBytes,
                  totalBytesWritten > maximumResponseBytes || totalBytesExpectedToWrite > maximumResponseBytes else { return }
            exceededMaximum.withLock { $0 = true }
            downloadTask.cancel()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
        let timing = Mutex<(firstByte: TimeInterval?, end: TimeInterval?, family: QualityIPFamily?)?>(nil)

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            guard let transaction = metrics.transactionMetrics.last,
                  transaction.resourceFetchType == .networkLoad,
                  let start = transaction.requestStartDate else { return }
            let address = transaction.remoteAddress ?? ""
            let family: QualityIPFamily?
            if IPv4Address(address) != nil || IPv6Address(address)?.isIPv4Mapped == true { family = .ipv4 }
            else if IPv6Address(address) != nil { family = .ipv6 }
            else { family = nil }
            timing.withLock {
                $0 = (transaction.responseStartDate?.timeIntervalSince(start), transaction.responseEndDate?.timeIntervalSince(start), family)
            }
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
