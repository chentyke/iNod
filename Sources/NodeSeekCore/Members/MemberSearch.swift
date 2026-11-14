public struct MemberSearchResponse: Decodable, Sendable { public let memberList: [SearchedMember] }
public struct SearchedMember: Decodable, Sendable, Identifiable {
    public let member_id: Int
    public let member_name: String
    public let bio: String?
    public let coin: Int?
    public var id: Int { member_id }
}
