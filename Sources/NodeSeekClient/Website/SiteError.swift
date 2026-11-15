import Foundation

public enum SiteError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "官网返回了无法读取的内容，请重试。"
        case .httpStatus(let status): "官网请求失败 (\(status))"
        case .message(let message): message
        }
    }

    public static func displayMessage(for error: any Error) -> String {
        if let networkError = error as? URLError {
            switch networkError.code {
            case .timedOut:
                return "连接超时，请检查网络后重试。"
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed:
                return "无法连接 NodeSeek，请检查网络后重试。"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
