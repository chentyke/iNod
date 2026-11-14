public struct SiteRequestKey: Hashable {
    public let userID: Int?
    public let kind: String
    public let path: String

    public init(userID: Int?, kind: String, path: String) {
        self.userID = userID
        self.kind = kind
        self.path = path
    }
}
