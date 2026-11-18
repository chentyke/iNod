import Foundation

public enum NetworkQualityExamples {
    public static let completed = makeReport()

    public static let partial: NetworkQualityReport = {
        var report = makeReport()
        report.ipv6 = .unavailable(.hostUnreachable)
        report.upload = .unavailable(.timedOut)
        return report
    }()

    public static let running: NetworkQualityReport = {
        var report = makeReport()
        report.state = .running
        report.finishedAt = nil
        report.currentStep = .download
        report.completedStepCount = 3
        report.download = .running
        report.upload = .pending
        return report
    }()

    public static let cancelled: NetworkQualityReport = {
        var report = running
        report.finishedAt = report.startedAt.addingTimeInterval(4)
        report.state = .cancelled
        report.currentStep = nil
        report.download = .cancelled
        return report
    }()

    public static let unavailable: NetworkQualityReport = {
        var report = NetworkQualityReport(startedAt: exampleDate)
        report.finishedAt = exampleDate
        report.network = .offline
        report.state = .interrupted(.offline)
        return report
    }()

    private static let exampleDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func makeReport() -> NetworkQualityReport {
        var report = NetworkQualityReport(startedAt: exampleDate)
        report.finishedAt = exampleDate.addingTimeInterval(8)
        report.state = .completed
        report.network = .wifi
        report.completedStepCount = NetworkQualityReport.Step.allCases.count
        let source = QualitySource(provider: "IPinfo", endpoint: URL(string: "https://ipinfo.io/json")!, checkedAt: exampleDate)
        let attribution = QualityIPAttribution(countryCode: "JP", region: "Tokyo", city: "Tokyo", asn: "AS64496", networkName: "Example Network")
        for (step, address, host) in [(NetworkQualityReport.Step.ipv4, "192.0.2.123", "api.ipify.org"),
                                     (.ipv6, "2001:db8:1234:5678:abcd:ef01:2345:6789", "api6.ipify.org")] {
            let echo = QualitySource(provider: "ipify", endpoint: URL(string: "https://\(host)/")!, checkedAt: exampleDate)
            let ip = QualityPublicIP(address: address, source: echo, attributionSource: source, attribution: .measured(attribution))
            if step == .ipv4 { report.ipv4 = .measured(ip) } else { report.ipv6 = .measured(ip) }
        }
        func speedSource(_ path: String) -> QualitySource {
            QualitySource(provider: "Cloudflare", endpoint: URL(string: "https://speed.cloudflare.com/\(path)")!, checkedAt: exampleDate)
        }
        report.latency = .measured(QualityLatency(source: speedSource("__down?bytes=0"), samples: [18.0, 21, 19, 20, 22].map {
            QualityLatencySample(checkedAt: exampleDate, node: "NRT", milliseconds: $0, issue: nil)
        }))
        report.download = .measured(QualityBandwidth(source: speedSource("__down"), samples: [
            QualityTransferSample(checkedAt: exampleDate, node: "NRT", bytes: 10_000_000, seconds: 0.45, issue: nil)
        ]))
        report.upload = .measured(QualityBandwidth(source: speedSource("__up"), samples: [
            QualityTransferSample(checkedAt: exampleDate, node: "NRT", bytes: 10_000_000, seconds: 0.95, issue: nil)
        ]))
        return report
    }
}

public enum AdvancedQualityExamples {
    public static let partial: AdvancedQualityReport = {
        let time = NetworkQualityExamples.completed.startedAt
        let web = QualitySource(provider: "YouTube", endpoint: URL(string: "https://www.youtube.com/")!, checkedAt: time)
        let drop = QualitySource(provider: "Spamhaus DROP", endpoint: URL(string: "https://www.spamhaus.org/drop/drop_v4.json")!, checkedAt: time)
        let blocklist = QualitySource(provider: "Blocklist.de", endpoint: URL(string: "https://lists.blocklist.de/lists/all.txt")!, checkedAt: time)
        let route = QualityRouteReport(
            host: "ipv4.pek-4134.endpoint.nxtrace.org", city: "北京", carrier: "中国电信", family: .ipv4,
            checkedAt: time, address: "192.0.2.10", sent: 5, received: 4,
            hops: [.init(number: 1, address: "192.0.2.1", milliseconds: 2), .init(number: 2, address: nil, milliseconds: nil),
                   .init(number: 3, address: "192.0.2.10", milliseconds: 30)], reachedDestination: true, issue: nil
        )
        return AdvancedQualityReport(
            basicReportID: NetworkQualityExamples.completed.id, startedAt: time, finishedAt: time.addingTimeInterval(10),
            services: [.init(source: web, result: .measured(.webpageAccessible(httpStatus: 200)))],
            ipReputation: [.init(source: drop, family: .ipv4, result: .measured(.notListed)),
                           .init(source: blocklist, family: .ipv4, result: .measured(.listed(reference: nil))),
                           .init(source: blocklist, family: .ipv6, result: .unavailable(.timedOut))],
            mail: .init(host: "portquiz.net", port: 25, checkedAt: time, result: .measured(.timedOut)),
            nat: [.init(host: "stun.nextcloud.com", port: 443, checkedAt: time, result: .unavailable(.unsupportedMeasurement), samples: [])],
            routes: [route]
        )
    }()
}

public enum HardwareQualityExamples {
    public static let completed: HardwareQualityReport = {
        let time = NetworkQualityExamples.completed.startedAt
        var report = HardwareQualityReport(
            id: UUID(), startedAt: time, deviceModel: "iPhone18,3", operatingSystem: "iOS 26.0",
            lowPowerMode: false, initialThermalState: .nominal
        )
        report.finishedAt = time.addingTimeInterval(4)
        report.finalThermalState = .fair
        report.state = .completed
        report.cpu = .measured(.init(bytes: HardwareQualityService.cpuBytes, seconds: 0.15, thermalState: .nominal))
        report.write = .measured(.init(bytes: HardwareQualityService.storageBytes, seconds: 0.4, thermalState: .nominal))
        report.read = .measured(.init(bytes: HardwareQualityService.storageBytes, seconds: 0.2, thermalState: .fair))
        return report
    }()
}
