import Foundation

public struct LuckyDraw: Hashable, Sendable {
    public enum ParsedInput: Equatable, Sendable {
        case draw(LuckyDraw)
        case post(PostAddress)
    }

    public var postID: Int
    public var revealTime: Date
    public var count: Int
    public var firstFloor: Int
    public var removeDuplicates: Bool

    public init(postID: Int, revealTime: Date, count: Int, firstFloor: Int = 1, removeDuplicates: Bool = true) {
        self.postID = postID
        self.revealTime = revealTime
        self.count = count
        self.firstFloor = firstFloor
        self.removeDuplicates = removeDuplicates
    }

    public var valid: Bool {
        postID > 0
            && count > 0
            && firstFloor >= 1
            && revealTime.timeIntervalSince1970.isFinite
            && (0...4_102_444_800).contains(revealTime.timeIntervalSince1970)
    }

    public var milliseconds: Int64 {
        Int64((revealTime.timeIntervalSince1970 * 1000).rounded())
    }

    public var url: URL {
        var c = URLComponents(url: NodeSeekRoute.origin.appending(path: "lucky"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "post", value: String(postID)),
            URLQueryItem(name: "time", value: String(milliseconds)),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "start", value: String(firstFloor)),
            URLQueryItem(name: "duplicate", value: removeDuplicates ? "false" : "true"),
            URLQueryItem(name: "mode", value: "view")
        ]
        return c.url!
    }

    public var markdownLink: String {
        "[开奖链接](\(url.absoluteString))"
    }

    public func isReadyToReveal(at now: Date = .now) -> Bool {
        revealTime <= now
    }

    public func winnersAnnouncement(_ winners: [LuckyFloor]) -> String {
        guard !winners.isEmpty else { return "" }
        return winners
            .map { EditorDraft.replyReference(postID: postID, floor: $0.floor_id, name: $0.member_name) }
            .joined(separator: " ") + "恭喜中奖🎁"
    }

    public static func parseInput(_ raw: String) -> ParsedInput? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if let markdownMatch = trimmed.wholeMatch(of: /^\[[^\]]*\]\(([^()\s]+)\)$/) {
            candidate = String(markdownMatch.1)
        } else {
            candidate = trimmed
        }

        if let normalizedURL = ForumURL.normalized(candidate), let draw = LuckyDraw(url: normalizedURL) {
            return .draw(draw)
        }
        if let directURL = URL(string: candidate), let draw = LuckyDraw(url: directURL) {
            return .draw(draw)
        }
        if let post = PostAddress(candidate) {
            return .post(post)
        }
        return nil
    }

    public static func validationMessage(postInput: String, countInput: String, firstFloorInput: String) -> String? {
        let trimmedPost = postInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPost.isEmpty else { return nil }
        guard parseInput(trimmedPost) != nil else {
            return "请输入有效的 NodeSeek 帖子编号、帖子链接或开奖链接。"
        }
        guard let count = Int(countInput.trimmingCharacters(in: .whitespacesAndNewlines)), count >= 1 else {
            return "中奖人数需为不小于 1 的整数。"
        }
        guard let firstFloor = Int(firstFloorInput.trimmingCharacters(in: .whitespacesAndNewlines)), firstFloor >= 1 else {
            return "起始楼层需从 1 楼开始。"
        }
        return nil
    }

    public init?(url: URL) {
        guard ["www.nodeseek.com", "nodeseek.com"].contains(url.host()?.lowercased() ?? ""),
              url.scheme?.lowercased() == "https",
              url.path == "/lucky",
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let q = Dictionary(c.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { first, _ in first })
        guard let id = Int(q["post"] ?? ""),
              let time = Double(q["time"] ?? ""),
              time.isFinite,
              abs(time) < 8_640_000_000_000_000,
              let count = Int(q["count"] ?? ""),
              let floor = Int(q["start"] ?? "") else {
            return nil
        }
        self.init(
            postID: id,
            revealTime: Date(timeIntervalSince1970: time / 1000),
            count: count,
            firstFloor: floor,
            removeDuplicates: q["duplicate"] == "false"
        )
        guard valid else { return nil }
    }

    public var round: Int {
        Int(floor((revealTime.timeIntervalSince1970 - 1_595_431_050) / 30))
    }

    public static let chain = "8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce"

    // The website uses cyrb128 + sfc32, then sorts one random value per floor.
    public static func order(seed: String, count: Int) -> [Int] {
        var a: UInt32 = 1779033703, b: UInt32 = 3144134277, c: UInt32 = 1013904242, d: UInt32 = 2773480762
        for character in seed.utf16 {
            let t = UInt32(character)
            a = b ^ ((a ^ t) &* 597399067); b = c ^ ((b ^ t) &* 2869860233)
            c = d ^ ((c ^ t) &* 951274213); d = a ^ ((d ^ t) &* 2716044179)
        }
        a = (c ^ (a >> 18)) &* 597399067; b = (d ^ (b >> 22)) &* 2869860233
        c = (a ^ (c >> 17)) &* 951274213; d = (b ^ (d >> 19)) &* 2716044179
        let first = a ^ b ^ c ^ d; b ^= a; c ^= a; d ^= a; a = first
        var values: [(UInt32, Int)] = []
        values.reserveCapacity(max(0, count))
        for index in 0..<max(0, count) {
            var value = a &+ b; a = b ^ (b >> 9); b = c &+ (c << 3); c = (c << 21) | (c >> 11)
            d &+= 1; value &+= d; c &+= value
            values.append((value, index))
        }
        values.sort { left, right in left.0 == right.0 ? left.1 < right.1 : left.0 < right.0 }
        return values.map { $0.1 }
    }

    public func winners(floors: [LuckyFloor], randomness: String) -> [LuckyFloor] {
        var seen = Set<Int>(), duplicates = Set<Int>()
        for (index, item) in floors.enumerated() where index >= firstFloor {
            if !seen.insert(item.member_id).inserted { duplicates.insert(index) }
        }
        return Self.order(seed: randomness, count: floors.count)
            .filter { floors[$0].floor_id >= firstFloor && (!removeDuplicates || !duplicates.contains($0)) }
            .prefix(count)
            .map { floors[$0] }
            .sorted { $0.floor_id < $1.floor_id }
    }
}

public struct LuckyFloor: Decodable, Sendable, Identifiable, Equatable {
    public let floor_id: Int
    public let member_id: Int
    public let member_name: String
    public var id: Int { floor_id }

    public init(floor_id: Int, member_id: Int, member_name: String) {
        self.floor_id = floor_id
        self.member_id = member_id
        self.member_name = member_name
    }
}

public struct LuckyFloorsResponse: Decodable, Sendable {
    public let success: Bool
    public let data: [LuckyFloor]
}
