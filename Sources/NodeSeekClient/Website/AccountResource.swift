import NodeSeekCore

public enum AccountResource: Hashable {
    case content(AccountContentKind, userID: Int, page: Int)
    case notices(NoticeKind)
    case messages
    case conversation(Int)
    case credit(Int)
    case stardust(userID: Int, cursor: Int?)
    case attendance(Int)
    case profile(Int)
    case editableProfile(Int)
    case security
    case blocks
    case homepage

    public var isPublic: Bool {
        switch self {
        case .profile, .content(.topics, _, _), .content(.replies, _, _): true
        default: false
        }
    }

    var memberID: Int? {
        switch self {
        case .profile(let id), .editableProfile(let id), .conversation(let id), .content(_, let id, _): id
        default: nil
        }
    }

    var lifetime: Double {
        switch self {
        case .notices, .messages, .conversation: 5
        case .attendance: 15
        case .profile, .editableProfile, .security, .blocks, .homepage: 120
        default: 30
        }
    }

    var kind: String {
        switch self {
        case .content(let kind, _, _): kind.rawValue
        case .notices: "notices"
        case .messages: "messages"
        case .conversation: "conversation"
        case .credit: "credit"
        case .stardust: "stardust"
        case .attendance: "attendance"
        case .profile, .editableProfile: "profile"
        case .security: "security"
        case .blocks: "blocks"
        case .homepage: "homepage"
        }
    }

    var page: Int {
        switch self {
        case .content(_, _, let page), .credit(let page), .attendance(let page): max(1, page)
        default: 1
        }
    }

    var path: String {
        switch self {
        case .content(let kind, let id, let page):
            switch kind {
            case .topics: "/api/content/list-discussions?uid=\(id)&page=\(max(1,page))"
            case .replies: "/api/content/list-comments?uid=\(id)&page=\(max(1,page))"
            case .collections: "/api/statistics/list-collection?page=\(max(1,page))"
            }
        case .notices(let kind): "/api/notification/\(kind.rawValue)/list"
        case .messages: "/api/notification/message/list"
        case .conversation(let id): "/api/notification/message/with/\(id)"
        case .credit(let page): "/api/account/credit/page-\(max(1,page))"
        case .stardust(let id, let cursor): "/api/stardust/list?member_id=\(id)&count=10" + (cursor.map { "&before_id=\($0)" } ?? "")
        case .attendance(let page): "/api/attendance/board?page=\(max(1,page))"
        case .profile(let id): "/api/account/getInfo/\(id)?readme=1"
        case .editableProfile(let id): "/api/account/getInfo/\(id)?readme=1&signature=1"
        case .security: "/api/account/otp-status"
        case .blocks: "/api/block-list/list"
        case .homepage: "/api/homepage"
        }
    }
}
