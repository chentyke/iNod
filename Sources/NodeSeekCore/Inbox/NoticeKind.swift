public enum NoticeKind: String, Hashable, CaseIterable, Identifiable, Sendable {
    case replies = "reply-to-me"
    case mentions = "at-me"

    public var id: Self { self }
}
