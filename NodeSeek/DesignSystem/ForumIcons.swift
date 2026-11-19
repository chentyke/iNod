import NodeSeekClient
import NodeSeekCore
import SwiftUI

extension ForumCategory {
    var inkIcon: ImageResource { Self.icon(for: id) }

    static func icon(for id: String) -> ImageResource {
        switch id {
        case "": .inkAllBoards
        case "daily": .inkCoffee
        case "tech": .inkTools
        case "info": .inkBulletin
        case "review": .inkReview
        case "trade": .inkSale
        case "carpool": .inkCarpool
        case "promotion": .inkPromotion
        case "life": .inkSprout
        case "dev": .inkTerminal
        case "photo-share": .inkCamera
        case "expose": .inkSpotlight
        case "inside": .inkMembersOnly
        case "meaningless": .inkChatter
        case "sandbox": .inkSandbox
        default: .inkUnknownBoard
        }
    }
}

extension HomepageCategory {
    var inkIcon: ImageResource { ForumCategory.icon(for: id) }
}

extension LoadFailure {
    var inkIcon: ImageResource {
        switch kind {
        case .offline: .inkOffline
        case .timedOut: .inkTimeout
        case .unreachable: .inkBrokenLink
        case .serverBusy: .inkBusyServer
        case .rateLimited: .inkHourglass
        case .verificationRequired: .inkVerifySite
        case .other: .inkFeedbackError
        }
    }
}

extension RulingRecord.ActionItem {
    var inkIcon: ImageResource {
        switch kind {
        case .coin: .inkAdjustDrumstick
        case .stardust: .inkAdjustDust
        case .title: .inkEditTitle
        case .category: .inkMoveBoard
        case .permission: symbol == "lock.open" ? .inkPublicPost : .inkReadPermission
        case .lock: symbol == "lock.open" ? .inkAllowEdit : .inkLockEdit
        case .award: .inkFeatured
        case .hideComment: symbol == "eye" ? .inkShowComment : .inkBlockedComment
        case .pinComment: symbol == "pin" ? .inkPinReply : .inkUnpinReply
        case .suspend: symbol == "nosign" ? .inkMute : .inkUnmute
        case .generic: .inkRulings
        }
    }
}

/// Use the same localized labels and system empty-state layout with a catalog image.
extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    init(_ title: LocalizedStringKey, image: ImageResource, description: Text? = nil) {
        self.init { SwiftUI.Label(title, image: image) } description: { description } actions: { EmptyView() }
    }

    init(_ title: String, image: ImageResource, description: Text? = nil) {
        self.init { SwiftUI.Label(title, image: image) } description: { description } actions: { EmptyView() }
    }
}
