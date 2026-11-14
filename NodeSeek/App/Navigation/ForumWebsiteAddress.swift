import Foundation

struct ForumWebsiteAddress: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
