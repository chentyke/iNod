import Foundation
import Network

public struct AdvancedNetworkQualityService: Sendable {
    public init() {}

    /// Run optional diagnostics. IP lists are checked against the addresses in the supplied report.
    public func run(for report: NetworkQualityReport) async -> AdvancedQualityReport {
        let startedAt = Date.now
        let session = QualityHTTP.makeSession()
        defer { session.invalidateAndCancel() }
        let send: QualityHTTP.Request = { try await QualityHTTP.request(using: session, request: $0, upload: $1) }
        async let access = Self.websiteAccess(send: send)
        async let reputation = QualityReputation.lookup(report: report, send: send)
        async let mail = Self.mailAccess()
        async let nat = QualitySTUN.measure()
        async let routes = QualityRoutes.measure(send: send)
        let results = await (access, reputation, mail, nat, routes)
        return AdvancedQualityReport(
            basicReportID: report.id, startedAt: startedAt, finishedAt: .now, services: results.0,
            ipReputation: results.1, mail: results.2, nat: results.3, routes: results.4
        )
    }

    static func websiteAccess(names: Set<String>? = nil, send: @escaping QualityHTTP.Request) async -> [QualityServiceAccess] {
        let sites = [
            ("Apple", "https://www.apple.com/"), ("Google", "https://www.google.com/"),
            ("YouTube", "https://www.youtube.com/"), ("GitHub", "https://github.com/"),
            ("ChatGPT", "https://chatgpt.com/")
        ]
        return await withTaskGroup(of: (Int, QualityServiceAccess).self) { group in
            for (index, site) in sites.enumerated() where names?.contains(site.0) != false {
                group.addTask {
                    let url = URL(string: site.1)!
                    let source = QualitySource(provider: site.0, endpoint: url, checkedAt: .now)
                    let result: QualityCheck<QualityServiceAccess.Result>
                    do {
                        try Task.checkCancellation()
                        var request = URLRequest(url: url, timeoutInterval: 5)
                        request.setValue("text/html", forHTTPHeaderField: "Accept")
                        let response = try await send(request, nil)
                        let status = response.statusCode
                        switch status {
                        case 200...299: result = .measured(.webpageAccessible(httpStatus: status))
                        case 300...399: result = .measured(.redirected(httpStatus: status))
                        case 451: result = .measured(.legallyRestricted(httpStatus: status))
                        default: result = .unavailable(.httpStatus(status))
                        }
                    } catch {
                        result = Task.isCancelled ? .cancelled : .unavailable(QualityIssue(error: error))
                    }
                    return (index, QualityServiceAccess(source: source, result: result))
                }
            }
            var results: [(Int, QualityServiceAccess)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func mailAccess() async -> QualityMailAccess {
        let host = "portquiz.net"
        let port: UInt16 = 25
        let checkedAt = Date.now
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port), using: .tcp)
        let updates = AsyncStream<NWConnection.State> { continuation in
            connection.stateUpdateHandler = { continuation.yield($0) }
            continuation.onTermination = { _ in connection.cancel() }
        }
        connection.start(queue: .init(label: "iNod.QualityMailAccess"))
        defer { connection.cancel() }
        let result: QualityCheck<QualityMailAccess.Result> = await withTaskGroup(of: QualityCheck<QualityMailAccess.Result>.self) { group in
            group.addTask {
                for await state in updates {
                    switch state {
                    case .ready: return .measured(.connected)
                    case .failed(.posix(.ECONNREFUSED)), .waiting(.posix(.ECONNREFUSED)): return .measured(.refused)
                    case .failed(.posix(.ETIMEDOUT)), .waiting(.posix(.ETIMEDOUT)): return .measured(.timedOut)
                    case .failed(.dns): return .unavailable(.hostUnreachable)
                    case .failed(let error): return .unavailable(.transportError((error as NSError).code))
                    case .cancelled: return .cancelled
                    default: break
                    }
                }
                return .cancelled
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(5))
                    return .measured(.timedOut)
                } catch { return .cancelled }
            }
            let first = await group.next() ?? .cancelled
            group.cancelAll()
            return first
        }
        return QualityMailAccess(host: host, port: port, checkedAt: checkedAt, result: result)
    }
}
