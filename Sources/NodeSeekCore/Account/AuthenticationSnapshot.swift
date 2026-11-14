public struct AuthenticationSnapshot: Decodable, Sendable {
    public let ready: Bool
    public let user: SignedInUser?
}
