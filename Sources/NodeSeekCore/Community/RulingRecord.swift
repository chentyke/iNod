import Foundation

public struct RulingPage: Decodable, Sendable {
    public var data: [RulingRecord]
    public let total: Int
}
public struct RulingRecord: Decodable, Sendable, Identifiable {
    public let id: Int
    public let target_member_id: Int
    public let target_member_name: String
    public let admin_member_id: Int
    public let admin_member_name: String
    public let post_id: Int
    public let floor_index: Int
    public let request: String
    public let created_at: String
    public var description: String {
        guard let object = try? JSONSerialization.jsonObject(with:Data(request.utf8)) as? [String:Any] else { return "管理操作" }
        var lines: [String] = []
        if let coin = object["coin"] as? [String:Any],let diff = coin["coin_diff"] as? Int { lines.append("鸡腿 \(diff >= 0 ? "+" : "")\(diff) · \(coin["reason"] as? String ?? "")") }
        if let dust = object["stardust"] as? [String:Any],let diff = dust["stardust_diff"] as? Int { lines.append("星尘 \(diff >= 0 ? "+" : "")\(diff)") }
        if let post = object["postSummary"] as? [String:Any] {
            if let title = post["title"] as? String { lines.append("标题改为：\(title)") }
            if let category = post["category"] as? String { lines.append("移到\(ForumCategory.all.first { $0.id == category }?.title ?? category)版块") }
            if let rank = post["rank"] as? Int { lines.append("阅读权限改为 \(rank == 255 ? "仅自己" : "Lv \(rank)")") }
            if let locked = post["locked"] as? Bool { lines.append(locked ? "禁止修改" : "允许修改") }
            if let award = post["award"] as? Bool { lines.append(award ? "加入推荐阅读" : "取消推荐阅读") }
        }
        if let hide = object["hideComment"] as? [String:Any],let status = hide["status"] as? Bool { lines.append(status ? "隐藏内容" : "取消隐藏内容") }
        if let pin = object["pinComment"] as? [String:Any],let status = pin["status"] as? Bool { lines.append(status ? "置顶回复" : "取消置顶回复") }
        if let ban = object["suspend"] as? [String:Any],let status = ban["status"] as? Bool { lines.append(status ? "禁言 \(ban["value"] as? Int ?? 0) 天" : "取消禁言") }
        return lines.isEmpty ? "管理操作" : lines.joined(separator:"\n")
    }
}
