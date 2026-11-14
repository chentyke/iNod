enum AccountLevel {
    static func from(coins: Int?) -> Int? {
        guard let coins else { return nil }
        return (0...6).reversed().first { coins >= 100 * $0 * $0 } ?? 0
    }
}
