public struct InvitationConfig: Decodable, Sendable, Equatable {
    public let payment: Payment

    public struct Payment: Decodable, Sendable, Equatable {
        public let coin: Option
        public let stardust: Option
    }

    public struct Option: Decodable, Sendable, Equatable {
        public let enabled: Bool
        public let cost: Int

        public func canAfford(with balance: Int?) -> Bool {
            enabled && (balance ?? -1) >= cost
        }

        public func shortfall(for balance: Int?) -> Int? {
            guard let balance, balance < cost else { return nil }
            return cost - balance
        }
    }
}

public struct InvitationPage: Decodable, Sendable, Equatable {
    public var data: [Invitation]
    public let total: Int

    public var availableCount: Int {
        data.filter { !$0.applied }.count
    }
}

public struct Invitation: Decodable, Sendable, Identifiable, Equatable {
    public let code: String
    public let applied: Bool
    public let created_at: String
    public var id: String { code }
}
