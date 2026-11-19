import Foundation

public struct RulingPage: Decodable, Sendable {
    public var data: [RulingRecord]
    public let total: Int

    private enum CodingKeys: String, CodingKey {
        case data, total
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([RulingRecord].self, forKey: .data)
        // A single-record response can omit the pagination total.
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? data.count
    }
}

public struct RulingRecord: Decodable, Sendable, Identifiable, Equatable {
    public struct ActionItem: Equatable, Sendable, Identifiable {
        public enum Kind: String, Equatable, Sendable {
            case coin, stardust, title, category, permission, lock, award, hideComment, pinComment, suspend, generic
        }

        public let id: String
        public let kind: Kind
        public let title: String
        public let summary: String
        public let symbol: String

        public init(id: String, kind: Kind, title: String, summary: String, symbol: String) {
            self.id = id
            self.kind = kind
            self.title = title
            self.summary = summary
            self.symbol = symbol
        }
    }

    public let id: Int
    public let target_member_id: Int
    public let target_member_name: String
    public let admin_member_id: Int
    public let admin_member_name: String
    public let post_id: Int
    public let floor_index: Int
    public let request: String
    public let created_at: String

    public var actionItems: [ActionItem] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(request.utf8)) as? [String: Any] else {
            return [Self.genericActionItem]
        }
        var items: [ActionItem] = []

        if let coin = object["coin"] as? [String: Any], let diff = coin["coin_diff"] as? Int {
            let reason = (coin["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let amount = "鸡腿 \(diff >= 0 ? "+" : "")\(diff)"
            let summary = reason.isEmpty ? amount : "\(amount) · \(reason)"
            items.append(ActionItem(id: "coin", kind: .coin, title: "鸡腿变动", summary: summary, symbol: "fork.knife"))
        }

        if let dust = object["stardust"] as? [String: Any], let diff = dust["stardust_diff"] as? Int {
            items.append(ActionItem(
                id: "stardust",
                kind: .stardust,
                title: "星尘变动",
                summary: "星尘 \(diff >= 0 ? "+" : "")\(diff)",
                symbol: "sparkles"
            ))
        }

        if let post = object["postSummary"] as? [String: Any] {
            if let title = post["title"] as? String {
                items.append(ActionItem(
                    id: "title",
                    kind: .title,
                    title: "修改标题",
                    summary: "标题改为：\(title)",
                    symbol: "character.cursor.ibeam"
                ))
            }
            if let category = post["category"] as? String {
                let categoryTitle = ForumCategory.all.first { $0.id == category }?.title ?? category
                items.append(ActionItem(
                    id: "category",
                    kind: .category,
                    title: "移动版块",
                    summary: "移到\(categoryTitle)版块",
                    symbol: "folder"
                ))
            }
            if let rank = post["rank"] as? Int {
                items.append(ActionItem(
                    id: "permission",
                    kind: .permission,
                    title: "阅读权限",
                    summary: "阅读权限改为 \(rank == 255 ? "仅自己" : "Lv \(rank)")",
                    symbol: rank == 0 ? "lock.open" : "lock"
                ))
            }
            if let locked = post["locked"] as? Bool {
                items.append(ActionItem(
                    id: "lock",
                    kind: .lock,
                    title: "编辑状态",
                    summary: locked ? "禁止修改" : "允许修改",
                    symbol: locked ? "lock" : "lock.open"
                ))
            }
            if let award = post["award"] as? Bool {
                items.append(ActionItem(
                    id: "award",
                    kind: .award,
                    title: "推荐阅读",
                    summary: award ? "加入推荐阅读" : "取消推荐阅读",
                    symbol: "rosette"
                ))
            }
        }

        if let hide = object["hideComment"] as? [String: Any], let status = hide["status"] as? Bool {
            items.append(ActionItem(
                id: "hideComment",
                kind: .hideComment,
                title: "内容可见性",
                summary: status ? "隐藏内容" : "取消隐藏内容",
                symbol: status ? "eye.slash" : "eye"
            ))
        }

        if let pin = object["pinComment"] as? [String: Any], let status = pin["status"] as? Bool {
            items.append(ActionItem(
                id: "pinComment",
                kind: .pinComment,
                title: "回复置顶",
                summary: status ? "置顶回复" : "取消置顶回复",
                symbol: status ? "pin" : "pin.slash"
            ))
        }

        if let ban = object["suspend"] as? [String: Any], let status = ban["status"] as? Bool {
            let days = ban["value"] as? Int ?? 0
            items.append(ActionItem(
                id: "suspend",
                kind: .suspend,
                title: "账号状态",
                summary: status ? "禁言 \(days) 天" : "取消禁言",
                symbol: status ? "nosign" : "checkmark.circle"
            ))
        }

        return items.isEmpty ? [Self.genericActionItem] : items
    }

    public var description: String {
        actionItems.map(\.summary).joined(separator: "\n")
    }

    public var primarySymbol: String {
        actionItems.first?.symbol ?? "list.bullet.rectangle"
    }

    public var shareURL: URL {
        URL(string: "https://www.nodeseek.com/ruling#/id-\(id)")!
    }

    public var associatedPostLocation: (post: PostSummary, page: Int, floor: Int?)? {
        guard post_id > 0, let address = PostAddress(String(post_id)) else { return nil }
        let page = PostAddress.page(forFloor: floor_index)
        let floor = floor_index > 0 ? floor_index : nil
        return (address.summary, page, floor)
    }

    public var associatedTargetTitle: String {
        floor_index == 0 ? "查看关联帖子" : "查看第 \(floor_index) 楼回复"
    }

    public var associatedShortLabel: String? {
        guard post_id > 0 else { return nil }
        return floor_index == 0
            ? "帖子 #\(String(post_id))"
            : "帖子 #\(String(post_id)) · #\(String(floor_index))"
    }

    /// Parses explicit record identifiers (`#801`, `id-801`, or a `/ruling#/id-801` URL) without treating plain usernames as IDs.
    public static func parseRecordID(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = trimmed.wholeMatch(of: /^(?:#|[iI][dD]-)(\d+)$/),
           let id = Int(match.1), id > 0 {
            return id
        }

        if let url = ForumURL.normalized(trimmed) ?? URL(string: trimmed),
           ["www.nodeseek.com", "nodeseek.com"].contains(url.host()?.lowercased() ?? ""),
           url.path == "/ruling",
           let fragment = url.fragment,
           let match = fragment.wholeMatch(of: /^\/?[iI][dD]-(\d+)$/),
           let id = Int(match.1), id > 0 {
            return id
        }

        return nil
    }

    private static let genericActionItem = ActionItem(
        id: "generic",
        kind: .generic,
        title: "管理操作",
        summary: "管理操作",
        symbol: "list.bullet.rectangle"
    )
}
