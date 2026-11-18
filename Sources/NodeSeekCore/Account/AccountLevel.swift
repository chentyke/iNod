public enum AccountLevel {
    public static let maxLevel = 6
    public static let tiers: [Tier] = (0...maxLevel).map { level in
        Tier(level: level, requiredCoins: requiredCoins(for: level))
    }

    public struct Tier: Equatable, Identifiable, Sendable {
        public let level: Int
        public let requiredCoins: Int
        public var id: Int { level }

        public init(level: Int, requiredCoins: Int) {
            self.level = level
            self.requiredCoins = requiredCoins
        }
    }

    public struct Progress: Equatable, Sendable {
        public let level: Int
        public let coins: Int
        public let currentFloor: Int
        public let nextLevel: Int?
        public let nextTarget: Int?

        public var isMaxLevel: Bool { nextLevel == nil }

        public var remainingCoins: Int? {
            guard let nextTarget else { return nil }
            return max(0, nextTarget - coins)
        }

        public var fraction: Double {
            guard let nextTarget else { return 1 }
            let span = max(1, nextTarget - currentFloor)
            return min(max(Double(coins - currentFloor) / Double(span), 0), 1)
        }

        public var compactSummary: String {
            if let remaining = remainingCoins {
                return "Lv \(level) · 还差 \(remaining.formatted())"
            }
            return "Lv \(level) · 已满级"
        }

        public var accessibilitySummary: String {
            if let nextLevel, let remaining = remainingCoins {
                return "Lv \(level)，距离 Lv \(nextLevel) 还差 \(remaining.formatted()) 个鸡腿"
            }
            return "Lv \(level)，已达最高等级"
        }
    }

    public static func requiredCoins(for level: Int) -> Int {
        let clamped = min(max(level, 0), maxLevel)
        return 100 * clamped * clamped
    }

    public static func from(coins: Int?) -> Int? {
        guard let coins else { return nil }
        return (0...maxLevel).reversed().first { coins >= requiredCoins(for: $0) } ?? 0
    }

    public static func progress(forCoins coins: Int?) -> Progress? {
        guard let coins, let level = from(coins: coins) else { return nil }
        let floor = requiredCoins(for: level)
        let next = level < maxLevel ? level + 1 : nil
        return Progress(
            level: level,
            coins: coins,
            currentFloor: floor,
            nextLevel: next,
            nextTarget: next.map(requiredCoins(for:))
        )
    }
}
