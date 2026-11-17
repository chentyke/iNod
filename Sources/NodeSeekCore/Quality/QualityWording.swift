import Foundation

// The words the report uses, shared by the screen and the shared text so they always agree.

public enum QualityFormat {
    /// 486 Mbps, 52.7 Mbps, 4.82 Mbps.
    public static func mbps(_ value: Double) -> String {
        let digits = value >= 100 ? 0 : value >= 10 ? 1 : 2
        return value.formatted(.number.precision(.fractionLength(digits)))
    }
    /// 31 ms, 2.1 ms.
    public static func ms(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value >= 10 ? 0 : 1)))
    }
    public static func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(value > 0 && value < 0.1 ? 1 : 0))) + "%"
    }
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
    public static func usage(_ range: ClosedRange<Int64>) -> String {
        let low = Double(range.lowerBound) / 1_000_000, high = Double(range.upperBound) / 1_000_000
        return "\(Int(low.rounded()))–\(Int(high.rounded())) MB"
    }

    /// Hides the part of an address that points at one subscriber: the last two IPv4 octets, everything after the
    /// first two IPv6 groups.
    public static func masked(_ address: String) -> String {
        if address.contains(":") {
            let groups = address.split(separator: ":", omittingEmptySubsequences: false)
            return groups.prefix(2).joined(separator: ":") + ":*:*"
        }
        let octets = address.split(separator: ".")
        guard octets.count == 4 else { return "***" }
        return octets.prefix(2).joined(separator: ".") + ".*.*"
    }
}

public extension NetworkQualityStep {
    var title: String {
        switch self {
        case .speed: "速度与延迟"
        case .ipv4: "公网 IPv4"
        case .ipv6: "公网 IPv6"
        case .routes: "三网线路"
        case .nat: "NAT 类型"
        case .mailPort: "邮件端口"
        case .reputation: "IP 信誉"
        case .services: "常用服务"
        }
    }
}

public extension DeviceBenchmarkStep {
    var title: String {
        switch self {
        case .cpuSingle: "CPU 单核"
        case .cpuMulti: "CPU 多核"
        case .storageSequential: "顺序读写"
        case .storageRandom: "随机读写"
        }
    }
}

public extension QualityStage {
    var title: String {
        switch self {
        case .findingServer: "正在选择测试节点"
        case .latency: "正在测延迟"
        case .download: "正在测下载"
        case .upload: "正在测上传"
        case .lookingUpOwner: "正在查询地址"
        case .tracing: "正在追踪路由"
        case .querying: "正在查询"
        }
    }
}

public extension QualityIssue {
    var title: String {
        switch kind {
        case .timedOut: "超时"
        case .offline: "网络已断开"
        case .networkChanged: "测试中网络发生切换"
        case .serviceUnavailable: "查询服务不可用"
        case .noIPv4: "当前网络没有 IPv4"
        case .noIPv6: "当前网络没有 IPv6"
        case .notSupported: "此设备不支持"
        case .refused: "连接被拒绝"
        case .rateLimited: "查询过于频繁"
        case .other: "无法完成"
        }
    }
}

public extension NetworkKind {
    var title: String {
        switch self { case .wifi: "Wi‑Fi"; case .cellular: "蜂窝网络"; case .wired: "有线网络"; case .other: "其他网络"; case .offline: "未连接" }
    }
}

public extension IPOwner {
    /// "中国 上海 · AS4812 中国电信"
    var summary: String {
        let place = [country, region == city ? nil : region, city].compactMap { $0 }.joined(separator: " ")
        let network = [asn.map { "AS\($0)" }, organization].compactMap { $0 }.joined(separator: " ")
        return [place, network].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public extension ChinaCarrier {
    var title: String { switch self { case .telecom: "电信"; case .unicom: "联通"; case .mobile: "移动" } }
}

public extension NATType {
    var title: String {
        switch self {
        case .openInternet: "公网直连"
        case .fullCone: "完全锥形"
        case .restrictedCone: "受限锥形"
        case .portRestrictedCone: "端口受限锥形"
        case .symmetric: "对称型"
        case .udpBlocked: "UDP 被阻断"
        case .undetermined: "无法确定"
        }
    }
    /// What the type means for the reader, in one line.
    var explanation: String {
        switch self {
        case .openInternet: "设备直接使用公网地址。"
        case .fullCone, .restrictedCone: "大多数点对点连接可以直接建立。"
        case .portRestrictedCone: "点对点连接通常可以建立，部分需要中转。"
        case .symmetric: "点对点连接通常需要中转，游戏和通话可能受影响。"
        case .udpBlocked: "当前网络不放行 UDP，通话和部分游戏无法直连。"
        case .undetermined: "测试没有得到足够的回应。"
        }
    }
}

public extension PortOutcome {
    var title: String {
        switch self { case .open: "可连接"; case .refused: "被拒绝"; case .timedOut: "连接超时"; case .undetermined: "无法确定" }
    }
}

public extension ReputationVerdict {
    var title: String {
        switch self { case .clean: "无风险"; case .low: "低风险"; case .medium: "中风险"; case .high: "高风险"; case .unknown: "未知" }
    }
}

public extension ServiceProbe {
    /// Never claims more than the check asked: a page load reads "网页可访问", not "可用".
    var outcomeTitle: String {
        switch (outcome, basis) {
        case (.reachable, .webPage): "网页可访问"
        case (.reachable, .regionCheck): region.map { "可用 · \($0)" } ?? "可用"
        case (.regionRestricted, _): region ?? "地区受限"
        case (.timedOut, _): "超时"
        case (.undetermined, _): "无法判断"
        }
    }
}

public extension ThermalLevel {
    var title: String { switch self { case .nominal: "正常"; case .fair: "略热"; case .serious: "较热"; case .critical: "过热" } }
}
