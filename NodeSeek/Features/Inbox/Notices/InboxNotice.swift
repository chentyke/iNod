import Foundation
import NodeSeekCore

struct InboxNotice: Identifiable {
    let notice: ForumNotice
    let kind: NoticeKind
    let date: Date?

    var id: String { "\(kind.rawValue)-\(notice.id)" }

    init(notice: ForumNotice, kind: NoticeKind) {
        self.notice = notice
        self.kind = kind
        date = ForumDate.parse(notice.createdAt)
    }
}
