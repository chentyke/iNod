import Foundation
import NodeSeekCore

public enum WebsiteResource {
    case connections(follows: Bool)
    case memberSearch(String)
    case dailyProgress
    case otpStatus
    case invitationConfig
    case invitations(page: Int)
    case rulings(recordID: Int?, page: Int, search: String)
    case stardust(memberID: Int, type: String, reference: String, peer: String, beforeID: Int?)
    case stardustPayment(memberID: Int, reference: Int, peerID: Int)
    case vote(Int)
    case voteVoters(itemID: Int, page: Int)
    case luckyFloors(LuckyDraw)

    public static func stardust(memberID: Int, filter: StardustFilter, beforeID: Int? = nil) -> Self {
        let clean = filter.normalized() ?? StardustFilter()
        return .stardust(
            memberID: memberID,
            type: clean.type,
            reference: clean.reference,
            peer: clean.peer,
            beforeID: beforeID
        )
    }

    var requiresLogin: Bool {
        switch self { case .vote, .voteVoters, .luckyFloors: false; default: true }
    }

    var path: String {
        switch self {
        case .connections(let follows): follows ? "/api/fans/follow" : "/api/fans/fans"
        case .memberSearch(let query): "/api/account/find/" + (query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))) ?? "")
        case .dailyProgress: "/api/progress/today"
        case .otpStatus: "/api/account/otp-status"
        case .invitationConfig: "/api/invite/config"
        case .invitations(let page): "/api/invite/list?page=\(page)"
        case .rulings(let recordID, let page, let search):
            queryPath(recordID.map { "/api/admin/ruling/id-\($0)" } ?? "/api/admin/ruling/page-\(page)",
                      search.isEmpty ? [] : [.init(name: "search", value: search)])
        case .stardust(let memberID, let type, let reference, let peer, let beforeID):
            queryPath("/api/stardust/list", [
                .init(name: "member_id", value: String(memberID)), .init(name: "count", value: "10")
            ] + [URLQueryItem(name: "type", value: type), .init(name: "ref_id", value: reference),
                 .init(name: "peer_id", value: peer)].filter { $0.value?.isEmpty == false }
                + (beforeID.map { [.init(name: "before_id", value: String($0))] } ?? []))
        case .stardustPayment(let memberID, let reference, let peerID):
            "/api/stardust/list?member_id=\(memberID)&ref_id=\(reference)&peer_id=\(peerID)&count=1"
        case .vote(let id): "/api/vote/info/\(id)"
        case .voteVoters(let itemID, let page): "/api/vote/voter-of-item?id=\(itemID)&page=\(page)"
        case .luckyFloors(let draw): "/api/content/floor-data?postId=\(draw.postID)&time=\(draw.milliseconds)"
        }
    }

    private func queryPath(_ path: String, _ items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = path
        if !items.isEmpty { components.queryItems = items }
        return components.string ?? path
    }
}
