import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct CommunityToolsView: View {
    @Environment(AccountSession.self) private var account
    var body: some View {
        List {
            Section("社区") {
                NavigationLink(value: AppDestination.recommended) { Label("推荐阅读",systemImage:"rosette") }
                NavigationLink(value: AppDestination.memberSearch) { Label("查找用户",systemImage:"person.crop.circle.badge.magnifyingglass") }
                NavigationLink(value: AppDestination.luckyDraw) { Label("抽奖工具",systemImage:"gift") }
                NavigationLink(value: AppDestination.rulings(recordID: nil)) { Label("管理记录",systemImage:"list.bullet.rectangle") }
                if let userID = account.user?.id { NavigationLink(value: AppDestination.invitations(userID: userID)) { Label("邀请朋友",systemImage:"ticket") } }
            }
            Section("发现") {
                NavigationLink(value: AppDestination.directory(providers: true)) { Label("合作商家",systemImage:"building.2") }
                NavigationLink(value: AppDestination.directory(providers: false)) { Label("友情链接",systemImage:"link") }
                Link(destination:URL(string:"https://rss.nodeseek.com")!) { Label("RSS 订阅",systemImage:"dot.radiowaves.left.and.right") }
                Link(destination:URL(string:"https://t.me/nodeseekc")!) { Label("电报频道",systemImage:"megaphone") }
                Link(destination:URL(string:"https://t.me/nodeseekg")!) { Label("电报群组",systemImage:"person.2") }
            }
            Section("NodeSeek") {
                NavigationLink(value: AppDestination.siteArticle(path: "about", title: "关于本站")) { Label("关于本站",systemImage:"info.circle") }
                NavigationLink(value: AppDestination.siteArticle(path: "termsofservice", title: "隐私协议")) { Label("隐私协议",systemImage:"hand.raised") }
                NavigationLink(value: AppDestination.post(PostAddress("6797")!.summary, page: 1, floor: nil)) { Label("商家申请规则",systemImage:"building.2.crop.circle") }
                NavigationLink(value: AppDestination.post(PostAddress("6800")!.summary, page: 1, floor: nil)) { Label("Premium Provider",systemImage:"checkmark.seal") }
                NavigationLink(value: AppDestination.post(PostAddress("361666")!.summary, page: 1, floor: nil)) { Label("广告合作",systemImage:"rectangle.badge.person.crop") }
                Link("联系 NodeSeek",destination:URL(string:"https://t.me/nodeseek")!)
            }
        }.seekGroupedList().navigationTitle("社区工具").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar).toolbar(.hidden,for:.tabBar)
    }
}
