import Foundation

import NodeSeekCore

public enum WebsiteAction {
    case attend(random: Bool)
    case updateProfile(bio: String, signature: String, readme: String)
    case follow(memberID: Int, followed: Bool)
    case block(name: String)
    case unblock(memberID: Int)
    case saveHomepage([HomepageCategory])
    case changePassword(old: String, new: String)
    case unbindTelegram
    case otp(enable: Bool, password: String)
    case readWebsitePreferences
    case saveWebsiteStyle(String)
    case saveFestiveStyle(Bool)
    case prepareTransfer(recipientID: Int)
    case transfer(recipientID: Int, amount: Int, reference: Int)
    case buyInvitation(payment: String)
    case vote(items: [Int])
    case lockVote(id: Int)
    case createVote(title: String, multiple: Bool, isPublic: Bool, options: [String])
    case publish(draft: EditorDraft, mode: EditorMode)
    case pinComment(id: Int, pinned: Bool)

    var request: (path: String, body: [String: Any], headers: [String: String], changesData: Bool) {
        switch self {
        case .attend(let random): ("/api/attendance?random=\(random)", [:], [:], true)
        case .updateProfile(let bio, let signature, let readme): ("/api/account/introduction", ["bio": bio, "signature": signature, "readme": readme], [:], true)
        case .follow(let id, let followed): (followed ? "/api/fans/del" : "/api/fans/add", ["followed_member_id": id], [:], true)
        case .block(let name): ("/api/block-list/add", ["block_member_name": name], [:], true)
        case .unblock(let id): ("/api/block-list/del", ["block_member_id": id], [:], true)
        case .saveHomepage(let values): ("/api/homepage", ["data": values.map { ["category": $0.id, "showInIndex": $0.enabled] as [String: Any] }], [:], true)
        case .changePassword(let old, let new): ("/api/account/changePassword", ["oldPassword": old, "password": new], [:], true)
        case .unbindTelegram: ("/api/account/unbind-telegram", [:], [:], true)
        case .otp(let enable, let password): ("/api/account/otp", ["action": enable ? "create" : "remove", "password": password], [:], true)
        case .readWebsitePreferences: ("/api/preference/list", ["keys": ["enable_festivous_style"]], [:], false)
        case .saveWebsiteStyle(let style): ("/api/style", ["style": style], [:], true)
        case .saveFestiveStyle(let enabled): ("/api/preference/set", ["enable_festivous_style": enabled], [:], true)
        case .prepareTransfer(let id): ("/api/stardust/payment-prepare", ["receiver_id": id, "origin": NodeSeekRoute.origin.absoluteString], [:], false)
        case .transfer(let id, let amount, let reference): ("/api/stardust/send", ["member_id": id, "diff": amount, "ref_id": reference], [:], true)
        case .buyInvitation(let payment): ("/api/invite/buyOne", ["payment": payment], [:], true)
        case .vote(let items): ("/api/vote/voteforitem", ["ids": items], [:], true)
        case .lockVote(let id): ("/api/vote/lock/\(id)", ["locked": true], [:], true)
        case .createVote(let title, let multiple, let isPublic, let options):
            ("/api/vote/info", ["title": title, "multiple": multiple, "isPublic": isPublic, "items": options], [:], true)
        case .publish(let draft, let mode):
            ("/api/content/\(mode.rawValue)", draft.body(for: mode), ["csrf-token": UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).description], true)
        case .pinComment(let id, let pinned): ("/api/content/pin-comment", ["commentId": id, "action": pinned ? "remove" : "add"], [:], true)
        }
    }
}
