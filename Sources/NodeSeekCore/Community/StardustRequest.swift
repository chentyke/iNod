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
    public let id: Int
    public let diff: Int
    public let result: Int
    public let type: String
    public let created_at: String
    public let peer_id: Int?
    public let ref_id: Int?
}
