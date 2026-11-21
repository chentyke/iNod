import Foundation

public struct SiteRequestKey: Hashable {
    public let userID: Int?
    public let kind: String
    public let path: String

    func isThread(_ id: Int) -> Bool {
        kind.hasPrefix("thread") && URL(string: path)?.path.hasPrefix("/post-\(id)-") == true
    }

    public init(userID: Int?, kind: String, path: String) {
        self.userID = userID
        self.kind = kind
        self.path = path
    }
}
