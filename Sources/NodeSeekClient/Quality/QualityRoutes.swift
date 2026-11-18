import Darwin
import Foundation
import Network

struct QualityRoutes {
    private struct Target: Sendable {
        let host: String
        let city: String
        let carrier: String
    }

    private static let targets = [
        Target(host: "ipv4.pek-4134.endpoint.nxtrace.org", city: "北京", carrier: "中国电信"),
        Target(host: "ipv4.pek-4837.endpoint.nxtrace.org", city: "北京", carrier: "中国联通"),
        Target(host: "ipv4.can-9808.endpoint.nxtrace.org", city: "广州", carrier: "中国移动")
    ]

    static func measure(hosts: Set<String>? = nil, send: @escaping QualityHTTP.Request) async -> [QualityRouteReport] {
        let reports = await withTaskGroup(of: (Int, QualityRouteReport).self) { group in
            for (index, target) in targets.enumerated() where hosts?.contains(target.host) != false {
                group.addTask { await QualityDatagrams.background { (index, measure(target)) } }
            }
            var results: [(Int, QualityRouteReport)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var publicAddresses: [String] = []
        for address in reports.flatMap(\.hops).compactMap(\.address) {
            if isPublic(address), !publicAddresses.contains(address) { publicAddresses.append(address) }
        }
        return await annotate(reports, addresses: Array(publicAddresses.prefix(12)), send: send)
    }

    private static func annotate(
        _ reports: [QualityRouteReport], addresses: [String], send: @escaping QualityHTTP.Request
    ) async -> [QualityRouteReport] {
        let networks = await withTaskGroup(of: (String, QualityIPAttribution?).self) { group in
            for address in addresses {
                group.addTask { (address, try? await NetworkQualityService.lookupAttribution(address: address, v6: false, send: send)) }
            }
            var results: [String: QualityIPAttribution] = [:]
            for await (address, network) in group { results[address] = network }
            return results
        }
        return reports.map { original in
            var report = original
            for i in report.hops.indices {
                if let address = report.hops[i].address { report.hops[i].network = networks[address] }
            }
            return report
        }
    }

    private static func measure(_ target: Target) -> QualityRouteReport {
        let checkedAt = Date.now
        var address: String?
        var sent = 0
        var delays: [Double] = []
        var hops: [QualityRouteReport.Hop] = []
        var reached = false
        var issue: QualityIssue?
        do {
            try Task.checkCancellation()
            let endpoint = try QualitySocketAddress.resolve(target.host, family: AF_INET)
            guard let ip = endpoint.host else { throw QualityIssue.hostUnreachable }
            address = ip
            let socket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
            guard socket >= 0 else { throw QualityIssue.transportError(Int(errno)) }
            defer { close(socket) }
            let identifier = UInt16.random(in: 1...UInt16.max)
            let nonce = (0..<8).map { _ in UInt8.random(in: .min ... .max) }
            try setTTL(64, socket: socket)
            for sequence in 1...5 {
                let request = echo(identifier: identifier, sequence: UInt16(sequence), nonce: nonce)
                let started = ContinuousClock.now
                try QualityDatagrams.send(request, to: endpoint, socket: socket)
                sent += 1
                if try probeReply(request, socket: socket, destination: ip, timeout: .milliseconds(450))?.atDestination == true {
                    delays.append(milliseconds(since: started))
                }
            }
            for hop in 1...24 {
                try setTTL(Int32(hop), socket: socket)
                let request = echo(identifier: identifier, sequence: UInt16(100 + hop), nonce: nonce)
                let started = ContinuousClock.now
                try QualityDatagrams.send(request, to: endpoint, socket: socket)
                let reply = try probeReply(request, socket: socket, destination: ip, timeout: .milliseconds(350))
                let ms = milliseconds(since: started)
                hops.append(.init(number: hop, address: reply?.address, milliseconds: reply == nil ? nil : ms))
                if reply?.atDestination == true {
                    reached = true
                    break
                }
            }
        } catch {
            issue = Task.isCancelled ? .cancelled : QualityIssue(error: error)
        }
        if issue == nil, !reached { issue = .timedOut }
        return QualityRouteReport(
            host: target.host, city: target.city, carrier: target.carrier, family: .ipv4, checkedAt: checkedAt,
            address: address, sent: sent, received: delays.count,
            averageLatencyMs: delays.isEmpty ? nil : delays.reduce(0, +) / Double(delays.count),
            hops: hops, reachedDestination: reached, issue: issue
        )
    }

    private static func milliseconds(since started: ContinuousClock.Instant) -> Double {
        let elapsed = started.duration(to: .now).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    private static func setTTL(_ value: Int32, socket: Int32) throws {
        var ttl = value
        guard setsockopt(socket, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw QualityIssue.transportError(Int(errno))
        }
    }

    private static func probeReply(
        _ request: [UInt8], socket: Int32, destination: String, timeout: Duration
    ) throws -> (address: String, atDestination: Bool)? {
        do {
            return try QualityDatagrams.receive(on: socket, until: .now.advanced(by: timeout)) { bytes, peer in
                guard let address = peer.host else { return nil }
                switch replyType(bytes, request: request) {
                case .echoReply where address == destination: return (address, true)
                case .timeExceeded: return (address, false)
                default: return nil
                }
            }
        } catch QualityIssue.timedOut {
            return nil
        }
    }

    private enum Reply { case echoReply, timeExceeded }

    private static func replyType(_ bytes: [UInt8], request: [UInt8]) -> Reply? {
        // Darwin's IPv4 ICMP socket prepends the IP header, including any options.
        guard let first = bytes.first, first >> 4 == 4 else { return nil }
        let position = Int(first & 0x0f) * 4
        guard position >= 20, bytes.count >= position + 8, bytes[position + 1] == 0 else { return nil }
        if bytes[position] == 0 {
            return bytes.dropFirst(position + 4).elementsEqual(request.dropFirst(4)) ? .echoReply : nil
        }
        let enclosed = position + 8
        guard bytes[position] == 11, bytes.count >= enclosed + 20, bytes[enclosed] >> 4 == 4,
              bytes[enclosed + 9] == UInt8(IPPROTO_ICMP) else { return nil }
        let length = Int(bytes[enclosed] & 0x0f) * 4
        let echo = enclosed + length
        guard length >= 20, bytes.count >= echo + 8, bytes[echo] == 8,
              bytes[(echo + 4)..<(echo + 8)].elementsEqual(request[4..<8]) else { return nil }
        return .timeExceeded
    }

    private static func echo(identifier: UInt16, sequence: UInt16, nonce: [UInt8]) -> [UInt8] {
        var packet: [UInt8] = [8, 0, 0, 0, UInt8(identifier >> 8), UInt8(truncatingIfNeeded: identifier),
                               UInt8(sequence >> 8), UInt8(truncatingIfNeeded: sequence)] + nonce
        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count, by: 2) { sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1]) }
        while sum > 0xffff { sum = (sum & 0xffff) + (sum >> 16) }
        let checksum = ~UInt16(sum)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(truncatingIfNeeded: checksum)
        return packet
    }

    private static func isPublic(_ address: String) -> Bool {
        guard let ip = IPv4Address(address) else { return false }
        let bytes = Array(ip.rawValue)
        return !ip.isLoopback && !ip.isLinkLocal && !ip.isMulticast && bytes[0] != 0 && bytes[0] < 224 &&
            bytes[0] != 10 && !(bytes[0] == 100 && (64...127).contains(bytes[1])) &&
            !(bytes[0] == 172 && (16...31).contains(bytes[1])) && !(bytes[0] == 192 && bytes[1] == 168)
    }
}
