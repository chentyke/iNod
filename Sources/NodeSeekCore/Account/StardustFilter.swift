import Foundation

public struct StardustFilter: Equatable, Sendable {
    public enum Chip: Equatable, Identifiable, Sendable {
        case type(String)
        case peer(String)
        case reference(String)

        public var id: String {
            switch self {
            case .type(let value): "type:\(value)"
            case .peer(let value): "peer:\(value)"
            case .reference(let value): "ref:\(value)"
            }
        }

        public var label: String {
            switch self {
            case .type(let value): "类型：\(StardustRecord.typeTitle(value))"
            case .peer(let value): "对方 UID \(value)"
            case .reference(let value): "Ref ID \(value)"
            }
        }
    }

    public var type: String
    public var peer: String
    public var reference: String

    public init(type: String = "", peer: String = "", reference: String = "") {
        self.type = type
        self.peer = peer
        self.reference = reference
    }

    /// Accepts either a positive integer UID or a NodeSeek `/space/{uid}` URL; empty input means unfiltered.
    public var normalizedPeer: String? {
        let trimmed = peer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let id = MemberAddress.parse(trimmed) else { return nil }
        return String(id)
    }

    /// Preserves ASCII digits for positive integer reference IDs (including leading zeros); empty input means unfiltered.
    public var normalizedReference: String? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let value = Int(trimmed), value > 0 else {
            return nil
        }
        return trimmed
    }

    public var isPeerValid: Bool { normalizedPeer != nil }
    public var isReferenceValid: Bool { normalizedReference != nil }
    public var isValid: Bool { isPeerValid && isReferenceValid }

    public func normalized() -> StardustFilter? {
        guard let peer = normalizedPeer, let reference = normalizedReference else { return nil }
        return StardustFilter(
            type: type.trimmingCharacters(in: .whitespacesAndNewlines),
            peer: peer,
            reference: reference
        )
    }

    public var isEmpty: Bool {
        type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && peer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var chips: [Chip] {
        var items: [Chip] = []
        let cleanType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanType.isEmpty { items.append(.type(cleanType)) }
        if let peer = normalizedPeer, !peer.isEmpty { items.append(.peer(peer)) }
        if let reference = normalizedReference, !reference.isEmpty { items.append(.reference(reference)) }
        return items
    }

    public func removing(_ chip: Chip) -> StardustFilter {
        var copy = self
        switch chip {
        case .type: copy.type = ""
        case .peer: copy.peer = ""
        case .reference: copy.reference = ""
        }
        return copy
    }
}
