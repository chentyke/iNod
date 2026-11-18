import Foundation

public struct MemberSearchResponse: Decodable, Sendable {
    public let memberList: [SearchedMember]

    public init(memberList: [SearchedMember]) {
        self.memberList = memberList
    }
}

public struct SearchedMember: Decodable, Sendable, Identifiable, Equatable {
    public let member_id: Int
    public let member_name: String
    public let bio: String?
    public let coin: Int?
    public var id: Int { member_id }

    public init(member_id: Int, member_name: String, bio: String? = nil, coin: Int? = nil) {
        self.member_id = member_id
        self.member_name = member_name
        self.bio = bio
        self.coin = coin
    }

    public var level: Int? {
        AccountLevel.from(coins: coin)
    }

    public var spaceURL: URL {
        NodeSeekRoute.origin.appending(path: "space/\(member_id)")
    }

    public var trimmedBio: String? {
        guard let trimmed = bio?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public var metadataText: String {
        var parts = ["UID \(String(member_id))"]
        if let level {
            parts.append("Lv \(level)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Parses a member lookup box input into an optional direct UID jump and/or a username query.
public struct MemberSearchQuery: Equatable, Sendable {
    public let directMemberID: Int?
    public let usernameQuery: String?

    public var isEmpty: Bool {
        directMemberID == nil && usernameQuery == nil
    }

    public init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            directMemberID = nil
            usernameQuery = nil
            return
        }

        if let parsedID = MemberAddress.parse(trimmed) {
            directMemberID = parsedID
            if trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) {
                usernameQuery = trimmed
            } else {
                usernameQuery = nil
            }
            return
        }

        if let match = trimmed.wholeMatch(of: /^(?:[uU][iI][dD][\s:#-]*)(\d+)$/),
           let id = Int(match.1), id > 0 {
            directMemberID = id
            usernameQuery = nil
            return
        }

        if let match = trimmed.wholeMatch(of: /^#(\d+)$/),
           let id = Int(match.1), id > 0 {
            directMemberID = id
            usernameQuery = nil
            return
        }

        directMemberID = nil
        let withoutAt = trimmed.hasPrefix("@")
            ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmed
        let lowered = withoutAt.lowercased()
        if withoutAt.isEmpty || lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            usernameQuery = nil
        } else {
            usernameQuery = withoutAt
        }
    }
}
