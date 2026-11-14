import Foundation
import NodeSeekCore

public enum WebsiteDocument {
    case directory(providers: Bool)
    case article(String)

    public var url: URL {
        switch self {
        case .directory(let providers): NodeSeekRoute.origin.appending(path: providers ? "providers" : "friends")
        case .article(let path): NodeSeekRoute.origin.appending(path: path)
        }
    }

    var extraction: String {
        switch self { case .directory: DirectoryScripts.read; case .article: SiteScripts.article }
    }
}
