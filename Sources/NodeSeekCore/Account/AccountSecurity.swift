public struct AccountSecurity: Decodable, Sendable {
    public let twoFactorEnabled: Bool
    public let history: [LoginRecord]
}
