import SwiftUI

/// Opens pages in the reader's own browser, never inside the app.
///
/// `openURL` won't do for the site's own pages: inside a forum stack it shows a forum link as a native page.
@MainActor
enum Browser {
    static func open(_ url: URL) { UIApplication.shared.open(url) }
}
