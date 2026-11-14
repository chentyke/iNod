import Foundation

public enum PostAccessError: LocalizedError, Equatable {
    case levelRequired(Int?)
    case signInRequired
    case privatePost

    public var errorDescription: String? {
        switch self {
        case .levelRequired(let rank?): "此帖需要 Lv \(rank) 才能查看"
        case .levelRequired(nil): "当前等级不足，无法查看此帖"
        case .signInRequired: "请登录后查看此帖"
        case .privatePost: "此帖仅作者可见"
        }
    }
}
