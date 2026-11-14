public struct InvitationConfig: Decodable, Sendable {
    public let payment: Payment
    public struct Payment: Decodable, Sendable { public let coin: Option; public let stardust: Option }
    public struct Option: Decodable, Sendable { public let enabled: Bool; public let cost: Int }
}
public struct InvitationPage: Decodable, Sendable {
    public var data: [Invitation]
    public let total: Int
}
public struct Invitation: Decodable, Sendable, Identifiable {
    public let code: String
    public let applied: Bool
    public let created_at: String
    public var id: String { code }
}
