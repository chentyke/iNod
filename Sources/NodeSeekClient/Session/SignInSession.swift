import NodeSeekCore
import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class SignInSession {
    public let page: WebPage
    public private(set) var verification = "loading"
    public private(set) var token = ""
    private var loaded = false
    private var verificationStarted = Date.now

    public init() {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .default()
        page = WebPage(configuration: configuration, navigationDecider: VerificationNavigation())
    }

    public func monitor() async {
        #if DEBUG
        if UITestNetwork.isActive {
            verification = "error"
            return
        }
        #endif
        do {
            if !loaded {
                loaded = true
                for try await event in page.load(html: SignInScripts.document, baseURL: NodeSeekRoute.origin) {
                    if event == .committed { break }
                }
            }
            while !Task.isCancelled {
                if let json = try? await page.callJavaScript("return JSON.stringify(window.__verification||{state:'loading',token:''});") as? String,
                   let state = try? JSONDecoder().decode(VerificationState.self, from: Data(json.utf8)) {
                    verification = state.state
                    token = state.token
                }
                if verification == "loading", Date.now.timeIntervalSince(verificationStarted) > 30 { verification = "error" }
                try await Task.sleep(for: .milliseconds(500))
            }
        } catch { if !Task.isCancelled { verification = "error"; token = "" } }
    }

    public func submit(body: [String: String], verificationToken: String = "") async throws -> SignInResponse {
        guard page.url?.scheme == "https", page.url?.host() == "www.nodeseek.com" else { throw SiteError.message("请先完成官网验证。") }
        let encoded = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        guard let json = try await page.callJavaScript(SignInScripts.submit, arguments: ["body": encoded, "token": verificationToken]) as? String else { throw SiteError.invalidResponse }
        let data = Data(json.utf8)
        if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], let error = result["__error"] as? String { throw SiteError.message(error) }
        return try JSONDecoder().decode(SignInResponse.self, from: data)
    }

    public func resetVerification() async {
        token = ""; verification = "loading"
        verificationStarted = .now
        _ = try? await page.callJavaScript("resetVerification();")
    }

    public func clear() { token = "" }
}

private struct VerificationState: Decodable { let state: String; let token: String }

private struct VerificationNavigation: WebPage.NavigationDeciding {
    private var loaded = false
    mutating func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if action.target?.isMainFrame == false { return .allow }
        guard !loaded, action.request.url?.host() == "www.nodeseek.com" else { return .cancel }
        loaded = true
        return .allow
    }
}
