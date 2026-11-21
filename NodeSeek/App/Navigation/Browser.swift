import NodeSeekClient
import SwiftUI

/// Opens pages in the reader's own browser, never inside the app.
///
/// `openURL` won't do for the site's own pages: inside a forum stack it shows a forum link as a native page.
@MainActor
enum Browser {
    static func open(_ url: URL) {
        #if DEBUG
        if UITestNetwork.isActive {
            guard let port = UInt16(exactly: UserDefaults.standard.integer(forKey: "uiTestBrowserPort")), port > 0 else { return }
            let local = URL(string: "http://127.0.0.1:\(port)/")!
            UIApplication.shared.open(local.appending(queryItems: [URLQueryItem(name: "url", value: url.absoluteString)]))
            return
        }
        #endif
        UIApplication.shared.open(url)
    }
}
