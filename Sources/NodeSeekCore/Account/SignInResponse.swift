public struct SignInResponse: Decodable, Sendable {
    public let success: Bool
    @WebsiteFlag public var need2FA: Bool?
    public let otpSession: String?
    public let message: String?
    public var isExpired: Bool { message?.contains("OTP_EXPIRED_OR_NOT_EXIST") == true }
}
