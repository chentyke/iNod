import Foundation

public struct ForumCategory: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let adminOnly: Bool

    public init(id: String, title: String, symbol: String, adminOnly: Bool = false) {
        self.id = id; self.title = title; self.symbol = symbol; self.adminOnly = adminOnly
    }

    private enum CodingKeys: String, CodingKey { case id = "key", title = "cn_text", symbol, adminOnly }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        guard !id.isEmpty, id.wholeMatch(of: /[a-zA-Z0-9_-]+/) != nil, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid forum category"))
        }
        let key = id
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol) ?? Self.all.first { $0.id == key }?.symbol ?? "bubble.left.and.bubble.right"
        adminOnly = try values.decodeIfPresent(WebsiteFlag.self, forKey: .adminOnly)?.wrappedValue ?? false
    }

    public static let all = [
        ForumCategory(id: "", title: "全部", symbol: "square.grid.2x2"),
        ForumCategory(id: "daily", title: "日常", symbol: "cup.and.saucer"),
        ForumCategory(id: "tech", title: "技术", symbol: "chevron.left.forwardslash.chevron.right"),
        ForumCategory(id: "info", title: "情报", symbol: "antenna.radiowaves.left.and.right"),
        ForumCategory(id: "review", title: "测评", symbol: "gauge.with.dots.needle.50percent"),
        ForumCategory(id: "trade", title: "交易", symbol: "arrow.left.arrow.right"),
        ForumCategory(id: "carpool", title: "拼车", symbol: "car"),
        ForumCategory(id: "promotion", title: "推广", symbol: "megaphone"),
        ForumCategory(id: "life", title: "生活", symbol: "leaf"),
        ForumCategory(id: "dev", title: "Dev", symbol: "terminal"),
        ForumCategory(id: "photo-share", title: "贴图", symbol: "photo"),
        ForumCategory(id: "expose", title: "曝光", symbol: "eye"),
        ForumCategory(id: "inside", title: "内版", symbol: "lock"),
        ForumCategory(id: "meaningless", title: "无意义", symbol: "ellipsis.bubble"),
        ForumCategory(id: "sandbox", title: "沙盒", symbol: "cube")
    ]
}
