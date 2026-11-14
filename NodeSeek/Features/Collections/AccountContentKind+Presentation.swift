import NodeSeekCore

extension AccountContentKind {
    var title: String {
        switch self { case .topics: "我的主题"; case .replies: "我的回复"; case .collections: "收藏" }
    }
    var symbol: String {
        switch self { case .topics: "text.bubble"; case .replies: "bubble.left"; case .collections: "bookmark" }
    }
}
