enum NotificationTab: String, CaseIterable, Identifiable {
    case activity = "互动"
    case messages = "私聊"

    var id: Self { self }
}
