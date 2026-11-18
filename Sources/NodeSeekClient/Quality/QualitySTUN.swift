import Darwin
import Foundation

struct QualitySTUN {
    private static let targets: [(host: String, port: UInt16)] = [("stun.nextcloud.com", 443), ("stun.miwifi.com", 3478)]
    private static let cookie: [UInt8] = [0x21, 0x12, 0xa4, 0x42]

    struct Endpoint: Equatable {
        let host: String
        let port: UInt16
    }

    struct Binding {
        let mapped: Endpoint
        let alternate: Endpoint?
    }

    static func measure() async -> [QualityNATReport] {
        await QualityDatagrams.background {
            var reports: [QualityNATReport] = []
            for target in targets {
                let report = measure(host: target.host, port: target.port)
                reports.append(report)
                if case .measured = report.result { break }
                if Task.isCancelled { break }
            }
            return reports
        }
    }

    private static func measure(host: String, port: UInt16) -> QualityNATReport {
        let start = Date.now
        var samples: [QualityNATReport.Sample] = []
        let result: QualityCheck<QualityNATReport.Mapping>
        do {
            try Task.checkCancellation()
            result = .measured(try observeMapping(host: host, port: port, samples: &samples))
        } catch {
            result = Task.isCancelled ? .cancelled : .unavailable(QualityIssue(error: error))
        }
        return QualityNATReport(host: host, port: port, checkedAt: start, result: result, samples: samples)
    }

    private static func observeMapping(
        host: String, port: UInt16, samples: inout [QualityNATReport.Sample]
    ) throws -> QualityNATReport.Mapping {
        let primary = try QualitySocketAddress.resolve(host, port: port, family: AF_INET)
        guard let primaryIP = primary.host else { throw QualityIssue.hostUnreachable }
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socket >= 0 else { throw QualityIssue.transportError(Int(errno)) }
        defer { close(socket) }

        let original = try bind(to: primary, socket: socket, samples: &samples)
        guard let alternate = original.alternate, alternate.host != primaryIP, alternate.port != port else {
            throw QualityIssue.unsupportedMeasurement
        }
        let differentAddress = try QualitySocketAddress.resolve(alternate.host, port: port, family: AF_INET)
        let second = try bind(to: differentAddress, socket: socket, samples: &samples)
        if original.mapped == second.mapped { return .endpointIndependent }
        let differentPort = try QualitySocketAddress.resolve(alternate.host, port: alternate.port, family: AF_INET)
        let third = try bind(to: differentPort, socket: socket, samples: &samples)
        return second.mapped == third.mapped ? .addressDependent : .addressAndPortDependent
    }

    private static func bind(to target: QualitySocketAddress, socket: Int32, samples: inout [QualityNATReport.Sample]) throws -> Binding {
        guard let host = target.host, let port = target.port else { throw QualityIssue.invalidResponse }
        let transaction = (0..<12).map { _ in UInt8.random(in: .min ... .max) }
        let request = [UInt8(0), 1, 0, 0] + cookie + transaction
        for duration in [Duration.milliseconds(1_500), .seconds(3)] {
            try QualityDatagrams.send(request, to: target, socket: socket)
            do {
                let binding = try QualityDatagrams.receive(on: socket, until: .now.advanced(by: duration)) { bytes, peer -> Binding? in
                    guard peer.host == host, peer.port == port else { return nil }
                    return parse(bytes, transaction: transaction)
                }
                samples.append(.init(target: "\(host):\(port)", publicAddress: binding.mapped.host, publicPort: binding.mapped.port))
                return binding
            } catch QualityIssue.timedOut {
                continue
            }
        }
        throw QualityIssue.timedOut
    }

    static func parse(_ bytes: [UInt8], transaction: [UInt8]) -> Binding? {
        guard bytes.count >= 20, bytes[0] == 1, bytes[1] == 1,
              bytes[4..<8].elementsEqual(cookie), bytes[8..<20].elementsEqual(transaction),
              Int(word(bytes, 2)) == bytes.count - 20 else { return nil }
        var offset = 20
        var mapped: Endpoint?
        var alternate: Endpoint?
        while offset + 4 <= bytes.count {
            let type = word(bytes, offset)
            let length = Int(word(bytes, offset + 2))
            let value = offset + 4
            let paddedLength = (length + 3) / 4 * 4
            guard value + paddedLength <= bytes.count else { return nil }
            if length == 8, bytes[value] == 0, bytes[value + 1] == 1 {
                if type == 0x0020 { mapped = endpoint(bytes, value: value, xor: true) }
                if type == 0x802c { alternate = endpoint(bytes, value: value, xor: false) }
            }
            offset = value + paddedLength
        }
        guard offset == bytes.count, let mapped else { return nil }
        return Binding(mapped: mapped, alternate: alternate)
    }

    private static func endpoint(_ bytes: [UInt8], value: Int, xor: Bool) -> Endpoint? {
        let port = word(bytes, value + 2) ^ (xor ? 0x2112 : 0)
        let ip = (0..<4).map { bytes[value + 4 + $0] ^ (xor ? cookie[$0] : 0) }
        guard port != 0, ip[0] > 0, ip[0] < 224, ip[0] != 10, ip[0] != 127,
              !(ip[0] == 169 && ip[1] == 254), !(ip[0] == 172 && (16...31).contains(ip[1])),
              !(ip[0] == 192 && ip[1] == 168) else { return nil }
        return Endpoint(host: ip.map(String.init).joined(separator: "."), port: port)
    }

    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
}
