import SwiftUI

enum NotificationTab: String, CaseIterable, Identifiable {
    case activity = "互动"
    case messages = "私聊"

    var id: Self { self }
    var other: Self { self == .activity ? .messages : .activity }

    static func animation(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.16 : 0.25)
    }
}
