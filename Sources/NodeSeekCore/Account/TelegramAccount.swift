public struct TelegramAccountResponse: Decodable, Sendable {
    public let telegramDetail: TelegramAccount?
}

public struct TelegramAccount: Decodable, Sendable {
    public let first_name: String?
    public let last_name: String?
    public let username: String?
    public let photo_url: String?
    public var displayName: String { [first_name, last_name].compactMap { $0 }.joined(separator: " ") }
}
