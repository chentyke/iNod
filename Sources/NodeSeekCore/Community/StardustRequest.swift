import Foundation

public struct StardustRequest: Hashable, Sendable {
    public let memberID: Int
    public let reference: Int
    public let amount: Int
    public let description: String
    public let once: Bool
    public init(memberID: Int,reference: Int,amount: Int,description: String,once: Bool) {
        self.memberID = memberID; self.reference = reference; self.amount = amount; self.description = description; self.once = once
    }
    public init?(_ input: String) {
        guard let url = URL(string:input),url.scheme == "nsapp",url.host() == "stardust-receive",let c = URLComponents(url:url,resolvingAgainstBaseURL:false) else { return nil }
        let q = Dictionary(c.queryItems?.map { ($0.name,$0.value ?? "") } ?? [],uniquingKeysWith:{ first,_ in first })
        guard let id = Int(q["member_id"] ?? ""),id > 0,let reference = Int(q["ref_id"] ?? ""),reference > 0,let amount = Int(q["diff"] ?? ""),amount > 0 else { return nil }
        self.init(memberID:id,reference:reference,amount:amount,description:q["description"] ?? "星尘收款",once:q["onetime"] == "true")
    }
    public var link: String {
        var c = URLComponents(); c.scheme = "nsapp"; c.host = "stardust-receive"
        c.queryItems = [URLQueryItem(name:"member_id",value:String(memberID)),URLQueryItem(name:"ref_id",value:String(reference)),URLQueryItem(name:"description",value:description),URLQueryItem(name:"diff",value:String(amount)),URLQueryItem(name:"onetime",value:once ? "true" : "false")]
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B")
        return c.string!
    }
}
public struct StardustRecords: Decodable, Sendable {
    public var records: [StardustRecord]
    public let exist_more: Bool?
    public let cursor: Int?
}
public struct StardustRecord: Decodable, Sendable, Identifiable {
    public static let filterableTypes = ["transfer", "upvote", "system", "buyCode", "admin"]

    public let id: Int
    public let diff: Int
    public let result: Int
    public let type: String
    public let created_at: String
    public let peer_id: Int?
    public let ref_id: Int?

    public init(
        id: Int,
        diff: Int,
        result: Int,
        type: String,
        created_at: String,
        peer_id: Int? = nil,
        ref_id: Int? = nil
    ) {
        self.id = id
        self.diff = diff
        self.result = result
        self.type = type
        self.created_at = created_at
        self.peer_id = peer_id
        self.ref_id = ref_id
    }

    public static func typeTitle(_ rawType: String) -> String {
        switch rawType {
        case "system": "系统"
        case "admin": "管理"
        case "transfer": "转账"
        case "upvote": "点赞"
        case "buyCode": "购买邀请码"
        default: rawType
        }
    }

    public var typeTitle: String { Self.typeTitle(type) }

    public var validPeerID: Int? {
        guard let peer_id, peer_id > 0 else { return nil }
        return peer_id
    }

    public var validRefID: Int? {
        guard let ref_id, ref_id > 0 else { return nil }
        return ref_id
    }

    public var formattedDiff: String {
        diff > 0 ? "+\(diff.formatted())" : diff.formatted()
    }
}
