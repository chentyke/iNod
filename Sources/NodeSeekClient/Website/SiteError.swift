import Foundation

public enum SiteError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case message(String)
    /// The site answered with a check or a sign-in the reader has to complete on the website.
    case verificationRequired

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "官网返回了无法读取的内容，请重试。"
        case .httpStatus(let status): "官网请求失败 (\(status))"
        case .message(let message): message
        case .verificationRequired: "官网需要完成验证，请打开官网后重试。"
        }
    }

    /// One readable sentence for `error`. See `LoadFailure` for the title and advice on their own.
    public static func displayMessage(for error: any Error, service: String = "NodeSeek") -> String {
        LoadFailure(error, service: service).message
    }
}
