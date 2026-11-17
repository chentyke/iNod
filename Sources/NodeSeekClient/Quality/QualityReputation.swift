import Foundation
import Network

struct QualityReputation {
    private struct DropEntry: Decodable {
        let cidr: String?
        let sblid: String?
        let timestamp: Int?
        let records: Int?
    }

    static func lookup(report: NetworkQualityReport, send: @escaping QualityHTTP.Request) async -> [QualityIPReputation] {
        let families: [(QualityIPFamily, QualityCheck<QualityPublicIP>)] = [(.ipv4, report.ipv4), (.ipv6, report.ipv6)]
        return await lookup(addresses: families.compactMap { family, check in check.value.map { (family, $0.address) } }, send: send)
    }

    static func lookup(
        addresses: [(QualityIPFamily, String)], ids: Set<String>? = nil, send: @escaping QualityHTTP.Request
    ) async -> [QualityIPReputation] {
        let targets = addresses.compactMap { family, address in addressBytes(address).map { (family, $0) } }
        guard !targets.isEmpty else { return [] }
        async let abuse = blocklist(targets: targets.filter { ids?.contains("Blocklist.de-\($0.0 == .ipv4 ? "v4" : "v6")") != false }, send: send)
        async let drop = withTaskGroup(of: QualityIPReputation.self) { group in
            for (family, bytes) in targets where ids?.contains("Spamhaus DROP-\(family == .ipv4 ? "v4" : "v6")") != false {
                group.addTask { await spamhaus(family: family, bytes: bytes, send: send) }
            }
            var items: [QualityIPReputation] = []
            for await item in group { items.append(item) }
            return items.sorted { $0.family.rawValue < $1.family.rawValue }
        }
        return await drop + abuse
    }

    private static func blocklist(
        targets: [(QualityIPFamily, [UInt8])], send: QualityHTTP.Request
    ) async -> [QualityIPReputation] {
        guard !targets.isEmpty else { return [] }
        let url = URL(string: "https://lists.blocklist.de/lists/all.txt")!
        let source = QualitySource(provider: "Blocklist.de", endpoint: url, checkedAt: .now)
        do {
            let response = try await send(URLRequest(url: url, timeoutInterval: 8), nil)
            try response.validateStatus()
            let lines = String(decoding: response.body, as: UTF8.self).split(whereSeparator: \.isNewline)
            let decoded = lines.compactMap { addressBytes(String($0)) }
            guard !decoded.isEmpty, decoded.count == lines.count else { throw QualityIssue.invalidResponse }
            let addresses = Set(decoded)
            return targets.map { family, bytes in
                let result: QualityCheck<QualityIPReputation.Verdict>
                if !addresses.contains(where: { $0.count == bytes.count }) {
                    result = .unavailable(.insufficientSamples)
                } else {
                    result = .measured(addresses.contains(bytes) ? .listed(reference: nil) : .notListed)
                }
                return QualityIPReputation(source: source, family: family, result: result)
            }
        } catch {
            let result: QualityCheck<QualityIPReputation.Verdict> = Task.isCancelled ? .cancelled : .unavailable(QualityIssue(error: error))
            return targets.map { QualityIPReputation(source: source, family: $0.0, result: result) }
        }
    }

    private static func spamhaus(family: QualityIPFamily, bytes: [UInt8], send: @escaping QualityHTTP.Request) async -> QualityIPReputation {
        let suffix = family == .ipv4 ? "v4" : "v6"
        let url = URL(string: "https://www.spamhaus.org/drop/drop_\(suffix).json")!
        let source = QualitySource(provider: "Spamhaus DROP", endpoint: url, checkedAt: .now)
        let result: QualityCheck<QualityIPReputation.Verdict>
        do {
            let response = try await send(URLRequest(url: url, timeoutInterval: 8), nil)
            try response.validateStatus()
            result = .measured(try dropVerdict(response.body, bytes: bytes))
        } catch {
            result = Task.isCancelled ? .cancelled : .unavailable(QualityIssue(error: error))
        }
        return QualityIPReputation(source: source, family: family, result: result)
    }

    static func dropVerdict(_ body: Data, bytes: [UInt8]) throws -> QualityIPReputation.Verdict {
        let lines = body.split(separator: 10)
        let decoder = JSONDecoder()
        let entries = try lines.map { try decoder.decode(DropEntry.self, from: Data($0)) }
        guard entries.count >= 2, let metadata = entries.last, metadata.timestamp != nil,
              metadata.records == entries.count - 1 else {
            throw QualityIssue.invalidResponse
        }
        var verdict: QualityIPReputation.Verdict = .notListed
        for entry in entries.dropLast() {
            guard let cidr = entry.cidr, let listed = matches(cidr: cidr, address: bytes) else {
                throw QualityIssue.invalidResponse
            }
            if listed { verdict = .listed(reference: entry.sblid) }
        }
        return verdict
    }

    private static func matches(cidr: String, address: [UInt8]) -> Bool? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let prefix = addressBytes(String(parts[0])), prefix.count == address.count,
              let bits = Int(parts[1]), (0...(8 * address.count)).contains(bits) else { return nil }
        let bytes = bits / 8
        guard prefix.prefix(bytes).elementsEqual(address.prefix(bytes)) else { return false }
        let remaining = bits % 8
        guard remaining > 0 else { return true }
        let mask = UInt8.max << (8 - remaining)
        return (prefix[bytes] & mask) == (address[bytes] & mask)
    }

    private static func addressBytes(_ address: String) -> [UInt8]? {
        if let ip = IPv4Address(address) { return Array(ip.rawValue) }
        if let ip = IPv6Address(address) { return Array(ip.rawValue) }
        return nil
    }
}
