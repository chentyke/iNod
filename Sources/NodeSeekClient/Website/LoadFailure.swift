import Foundation
import WebKit

/// What went wrong with a request, in words a reader understands, and what they can do about it.
///
/// Every error shown to the reader goes through here, so the system's own text such as
/// "NSURLErrorDomain 错误 -1009" never reaches the screen.
public struct LoadFailure: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The device has no usable network.
        case offline
        /// The network is there but the service took too long to answer.
        case timedOut
        /// The service's address can't be found or reached, or the secure connection failed.
        case unreachable
        /// The service answered with a server error.
        case serverBusy
        /// The service turned the request away for coming too often.
        case rateLimited
        /// The site wants the reader to pass a check or sign in on the website first.
        case verificationRequired
        /// Anything else.
        case other
    }

    public let kind: Kind
    /// A few words for the top of a page: "网络未连接".
    public let title: String
    /// One line on what happened and what to do next.
    public let advice: String

    /// The title and advice as one sentence, for alerts and inline notes.
    public var message: String { title == Self.genericTitle ? advice : "\(title)，\(advice)" }

    public var systemImage: String {
        switch kind {
        case .offline: "wifi.slash"
        case .timedOut: "clock.badge.exclamationmark"
        case .unreachable: "network.slash"
        case .serverBusy: "server.rack"
        case .rateLimited: "hourglass"
        case .verificationRequired: "checkmark.shield"
        case .other: "exclamationmark.circle"
        }
    }

    /// Whether the cause is the connection rather than what the site said, so trying again may help by itself.
    public var isConnectionProblem: Bool { [.offline, .timedOut, .unreachable].contains(kind) }

    public init(kind: Kind, title: String, advice: String) {
        self.kind = kind
        self.title = title
        self.advice = advice
    }

    /// A failure the app describes itself, such as "登录账号已变化，请刷新页面。"
    public init(message: String) {
        self.init(kind: .other, title: Self.genericTitle, advice: message)
    }

    /// Describes `error` for a request to `service`.
    public init(_ error: any Error, service: String = "NodeSeek") {
        self = Self.describe(error, service: service)
    }

    static let genericTitle = "暂时无法加载"

    private static func describe(_ error: any Error, service: String) -> LoadFailure {
        if let kind = connectionKind(of: error) { return connection(kind, service: service) }
        switch error {
        case let error as SiteError:
            switch error {
            case .verificationRequired:
                return connection(.verificationRequired, service: service)
            case .httpStatus(let status):
                return forStatus(status, service: service) ?? LoadFailure(message: "\(service) 返回了错误（\(status)），请稍后重试。")
            case .message(let text):
                if let code = statusCode(in: text), let failure = forStatus(code, service: service) { return failure }
                // Messages the site or the app wrote are already readable; a script's own English error is not.
                return text.contains(where: \.isHan) ? LoadFailure(message: text) : generic
            case .invalidResponse:
                return LoadFailure(message: error.errorDescription ?? generic.advice)
            }
        case let error as PostAccessError:
            return LoadFailure(message: error.errorDescription ?? generic.advice)
        case is DecodingError:
            return LoadFailure(message: "\(service) 返回了无法读取的内容，请稍后重试。")
        default:
            return generic
        }
    }

    private static let generic = LoadFailure(message: "出了点问题，请稍后重试。")

    private static func connection(_ kind: Kind, service: String) -> LoadFailure {
        switch kind {
        case .offline: LoadFailure(kind: kind, title: "网络未连接", advice: "请检查网络设置后重试。")
        case .timedOut: LoadFailure(kind: kind, title: "连接超时", advice: "网络较慢或 \(service) 响应慢，请稍后重试。")
        case .unreachable: LoadFailure(kind: kind, title: "无法连接 \(service)", advice: "请检查网络后重试。")
        case .serverBusy: LoadFailure(kind: kind, title: "\(service) 暂时不可用", advice: "服务器繁忙或正在维护，请稍后重试。")
        case .rateLimited: LoadFailure(kind: kind, title: "请求太频繁", advice: "请稍等片刻再重试。")
        case .verificationRequired: LoadFailure(kind: kind, title: "需要在官网完成验证", advice: "打开官网完成验证后，再回来重试。")
        case .other: generic
        }
    }

    private static func forStatus(_ status: Int, service: String) -> LoadFailure? {
        switch status {
        case 403: connection(.verificationRequired, service: service)
        case 429: connection(.rateLimited, service: service)
        case 500...599: connection(.serverBusy, service: service)
        default: nil
        }
    }

    /// The status code in the app's own "请求失败 (502)" style messages.
    private static func statusCode(in text: String) -> Int? {
        guard text.contains("请求失败") || text.contains("未返回可读取的数据"),
              let match = text.firstMatch(of: /\((\d{3})\)。?$/) else { return nil }
        return Int(match.1)
    }

    /// Finds a URL loading error, including one WebKit or another error wraps.
    private static func connectionKind(of error: any Error, depth: Int = 0) -> Kind? {
        guard depth < 4 else { return nil }
        if let navigation = error as? WebPage.NavigationError,
           case .failedProvisionalNavigation(let underlying) = navigation {
            return connectionKind(of: underlying, depth: depth + 1)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, let kind = kind(for: URLError.Code(rawValue: nsError.code)) {
            return kind
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error {
            return connectionKind(of: underlying, depth: depth + 1)
        }
        return nil
    }

    private static func kind(for code: URLError.Code) -> Kind? {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive:
            .offline
        case .timedOut:
            .timedOut
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed,
             .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired,
             .cannotLoadFromNetwork, .appTransportSecurityRequiresSecureConnection:
            .unreachable
        case .badServerResponse, .zeroByteResource, .cannotParseResponse:
            .serverBusy
        default:
            nil
        }
    }
}

private extension Character {
    /// A Chinese character, which marks text written for the reader rather than by a script engine.
    var isHan: Bool { unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
}
