import Foundation

public extension NetworkQualityReport {
    /// Plain text for copying and sharing. It holds exactly what the report shows, with addresses masked when asked.
    func sharedText(hidingAddresses: Bool, timeZone: TimeZone = .current) -> String {
        var lines = ["iNod 网络检测", "\(network.kind.title)，\(Self.timestamp(startedAt, timeZone))"]
        if network.usesVPN { lines[1] += "，经由 VPN" }

        func section(_ title: String, _ body: [String]) { lines.append(""); lines.append("【\(title)】"); lines += body }
        func line(_ result: QualityStatus) -> String? {
            switch result {
            case .failed(let issue), .unavailable(let issue): issue.title
            case .cancelled: "已取消"
            case .pending, .running: "未完成"
            case .measured, .notIncluded: nil
            }
        }

        if speed != .notIncluded {
            if let speed = speed.value {
                var body = [
                    (speed.downloadIsEstimate == true ? "下载约 " : "下载 ") + (speed.downloadMbps.map { QualityFormat.mbps($0) + " Mbps" } ?? "未测得"),
                    (speed.uploadIsEstimate == true ? "上传约 " : "上传 ") + (speed.uploadMbps.map { QualityFormat.mbps($0) + " Mbps" } ?? "未测得"),
                ]
                if let latency = speed.latencyMs { body.append("延迟 \(QualityFormat.ms(latency)) ms" + (speed.jitterMs.map { "，抖动 \(QualityFormat.ms($0)) ms" } ?? "")) }
                let node = [speed.server.provider, speed.server.location].filter { !$0.isEmpty }.joined(separator: " ")
                body.append("节点 \(node)")
                body += speed.issues.map { [$0.detail, $0.title].compactMap { $0 }.joined(separator: "，") }
                section("速度", body)
            } else if let text = line(speed.status) { section("速度", [text]) }
        }

        var addressLines: [String] = []
        for (family, result) in [(IPFamily.v4, ipv4), (.v6, ipv6)] where result != .notIncluded {
            let name = family == .v4 ? "IPv4" : "IPv6"
            if let egress = result.value {
                addressLines.append("\(name) \(hidingAddresses ? QualityFormat.masked(egress.address) : egress.address)")
                if let owner = egress.owner { addressLines.append("  \(owner.summary)") }
                else if let issue = egress.ownerIssue { addressLines.append("  归属：\(issue.title)") }
            } else if let text = line(result.status) { addressLines.append("\(name) \(text)") }
        }
        if !addressLines.isEmpty { section("公网地址", addressLines) }

        if routes != .notIncluded {
            if let traces = routes.value {
                section("三网线路", traces.map { trace in
                    let head = "\(trace.carrier.title) \(trace.city)"
                    if let issue = trace.issue { return "\(head) \(issue.title)" }
                    let loss = trace.lossRate.map { "丢包 \(QualityFormat.percent($0))" } ?? ""
                    let latency = trace.averageLatencyMs.map { "\(QualityFormat.ms($0)) ms，" } ?? ""
                    return "\(head) \(latency)\(loss)"
                })
            } else if let text = line(routes.status) { section("三网线路", [text]) }
        }
        if nat != .notIncluded {
            let notes = [nat.value?.type.title ?? line(nat.status), nat.value?.issue.map { $0.detail ?? $0.title }]
            section("NAT 类型", notes.compactMap { $0 })
        }
        if mailPort != .notIncluded { section("邮件端口", [mailPort.value.map { "TCP \($0.port) \($0.outcome.title)" } ?? line(mailPort.status) ?? ""]) }
        if reputation != .notIncluded {
            if let records = reputation.value {
                section("IP 信誉", records.map { record in
                    let family = record.family == .v4 ? "IPv4" : "IPv6"
                    if let issue = record.issue { return "\(record.source) \(family) \(issue.title)" }
                    return "\(record.source) \(family) \(record.verdict.title)" + (record.label.map { "（\($0)）" } ?? "")
                })
            } else if let text = line(reputation.status) { section("IP 信誉", [text]) }
        }
        if services != .notIncluded {
            if let probes = services.value { section("常用服务", probes.map { "\($0.name) \($0.outcomeTitle)" }) }
            else if let text = line(services.status) { section("常用服务", [text]) }
        }
        return lines.joined(separator: "\n")
    }

    private static func timestamp(_ date: Date, _ zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "zh_CN"))
        style.timeZone = zone
        return date.formatted(style)
    }
}
