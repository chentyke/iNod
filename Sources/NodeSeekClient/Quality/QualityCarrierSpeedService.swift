import Foundation
import NodeSeekCore

/// One operator's speed test endpoints.
public struct QualityCarrierSpeedNode: Codable, Equatable, Sendable {
    public enum Format: String, Codable, Sendable {
        case libreSpeed, speedTestCN
    }

    public static let taiyuanUnicom = Self(
        carrier: .unicom, city: "太原",
        latencyURL: URL(string: "https://node-218-26-162-114.speedtest.cn:51090/hello")!,
        downloadURL: URL(string: "https://node-218-26-162-114.speedtest.cn:51090/download")!,
        uploadURL: URL(string: "https://node-218-26-162-114.speedtest.cn:51090/upload")!,
        format: .speedTestCN
    )

    public let carrier: ChinaCarrier
    public let city: String
    public let latencyURL: URL
    public let downloadURL: URL
    public let uploadURL: URL
    public let format: Format?

    public init(
        carrier: ChinaCarrier, city: String, latencyURL: URL, downloadURL: URL, uploadURL: URL, format: Format? = nil
    ) {
        self.carrier = carrier
        self.city = city
        self.latencyURL = latencyURL
        self.downloadURL = downloadURL
        self.uploadURL = uploadURL
        self.format = format
    }

    fileprivate var isValid: Bool {
        guard let host = downloadURL.host(), latencyURL.path() != downloadURL.path() else { return false }
        return [latencyURL, downloadURL, uploadURL].allSatisfy { url in
            guard url.scheme == "https", url.host() == host, url.port == downloadURL.port else { return false }
            return url.user() == nil && url.password() == nil && url.query() == nil && url.fragment() == nil
        }
    }
}

public struct QualityCarrierSpeedResult: Codable, Equatable, Sendable {
    public let node: QualityCarrierSpeedNode
    public let report: NetworkQualityReport
}

/// Runs the same timing and speed calculations as the base check against a configured carrier node.
public struct QualityCarrierSpeedService: Sendable {
    private static let transferSizes = [1, 4, 4].map { $0 * 1_048_576 }
    public static let maximumTransferBytesPerNode = transferSizes.reduce(0, +) * 2

    private let request: QualityHTTP.Request?
    private let paths: @Sendable () -> AsyncStream<QualityNetworkPath>

    public init() {
        self.init(request: nil, paths: QualityNetworkPath.updates)
    }

    init(request: QualityHTTP.Request?, paths: @escaping @Sendable () -> AsyncStream<QualityNetworkPath>) {
        self.request = request
        self.paths = paths
    }

    public func run(
        at node: QualityCarrierSpeedNode,
        onProgress: @escaping @Sendable (NetworkQualityReport) async -> Void = { _ in }
    ) async throws -> QualityCarrierSpeedResult {
        guard node.isValid else { throw QualityIssue.invalidResponse }
        let isSpeedTestCN = node.format == .speedTestCN
        let target = NetworkQualityService.SpeedTarget(
            provider: isSpeedTestCN ? "SpeedTest.cn" : "LibreSpeed",
            latencyURL: node.latencyURL, downloadURL: node.downloadURL, uploadURL: node.uploadURL,
            downloadSizes: isSpeedTestCN ? [10 * 1_048_576] : Self.transferSizes,
            uploadSizes: isSpeedTestCN ? [4 * 1_048_576, 4 * 1_048_576] : Self.transferSizes,
            format: isSpeedTestCN ? .speedTestCN : .libreSpeed
        )
        let report = await NetworkQualityService(request: request, paths: paths, speedTarget: target)
            .run(steps: [.latency, .download, .upload], onProgress: onProgress)
        return QualityCarrierSpeedResult(node: node, report: report)
    }
}
