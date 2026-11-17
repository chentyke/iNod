import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct CommunityToolsView: View {
    @Environment(AccountSession.self) private var account
    var body: some View {
        List {
            Section("社区") {
                NavigationLink(value: AppDestination.recommended) { SeekRowLabel(title: "推荐阅读", symbol: "rosette") }
                NavigationLink(value: AppDestination.memberSearch) { SeekRowLabel(title: "查找用户", symbol: "person.crop.circle.badge.magnifyingglass") }
                NavigationLink(value: AppDestination.luckyDraw) { SeekRowLabel(title: "抽奖工具", symbol: "gift") }
                NavigationLink(value: AppDestination.rulings(recordID: nil)) { SeekRowLabel(title: "管理记录", symbol: "list.bullet.rectangle") }
                if let userID = account.user?.id { NavigationLink(value: AppDestination.invitations(userID: userID)) { SeekRowLabel(title: "邀请朋友", symbol: "ticket") } }
            }
            Section("检测") {
                NavigationLink(value: AppDestination.networkQuality) { SeekRowLabel(title: "网络检测", symbol: "gauge.with.needle") }
                NavigationLink(value: AppDestination.deviceBenchmark) { SeekRowLabel(title: "本机性能", symbol: "cpu") }
            }
            Section("发现") {
                NavigationLink(value: AppDestination.directory(providers: true)) { SeekRowLabel(title: "合作商家", symbol: "building.2") }
                NavigationLink(value: AppDestination.directory(providers: false)) { SeekRowLabel(title: "友情链接", symbol: "link") }
                Link(destination: URL(string: "https://rss.nodeseek.com")!) { SeekRowLabel(title: "RSS 订阅", symbol: "dot.radiowaves.left.and.right", opensExternally: true) }
                Link(destination: URL(string: "https://t.me/nodeseekc")!) { SeekRowLabel(title: "电报频道", symbol: "megaphone", opensExternally: true) }
                Link(destination: URL(string: "https://t.me/nodeseekg")!) { SeekRowLabel(title: "电报群组", symbol: "person.2", opensExternally: true) }
            }
            Section("NodeSeek") {
                NavigationLink(value: AppDestination.siteArticle(path: "about", title: "关于本站")) { SeekRowLabel(title: "关于本站", symbol: "info.circle") }
                NavigationLink(value: AppDestination.siteArticle(path: "termsofservice", title: "隐私协议")) { SeekRowLabel(title: "隐私协议", symbol: "hand.raised") }
                NavigationLink(value: AppDestination.post(PostAddress("6797")!.summary, page: 1, floor: nil)) { SeekRowLabel(title: "商家申请规则", symbol: "building.2.crop.circle") }
                NavigationLink(value: AppDestination.post(PostAddress("6800")!.summary, page: 1, floor: nil)) { SeekRowLabel(title: "Premium Provider", symbol: "checkmark.seal") }
                NavigationLink(value: AppDestination.post(PostAddress("361666")!.summary, page: 1, floor: nil)) { SeekRowLabel(title: "广告合作", symbol: "rectangle.badge.person.crop") }
                Link(destination: URL(string: "https://t.me/nodeseek")!) { SeekRowLabel(title: "联系 NodeSeek", symbol: "paperplane", opensExternally: true) }
            }
        }.seekGroupedList().navigationTitle("社区工具").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar).toolbar(.hidden,for:.tabBar)
    }
}
