public struct OTPSetup: Decodable, Sendable {
    public let secret: String
    public let uri: String
}
