import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct SiteArticleView: View {
    @Environment(AccountSession.self) private var account
    let path: String
    let title: String
    @State private var loader = ResourceLoader<String>()
    var body: some View {
        ResourceContent(loader:loader,websiteURL:NodeSeekRoute.origin.appending(path:path),retry:{ await load(force:true) }) { content in ScrollView { ForumMarkdown(markdown:content).padding(20).frame(maxWidth:.infinity,alignment:.leading) }.readableContentMargins(.keepsGutter, in: .scrollView) }
            .navigationTitle(title).task { await load() }
    }
    private func load(force: Bool = false) async {
        await loader.load(account.website, .article(path), force: force)
    }
}
