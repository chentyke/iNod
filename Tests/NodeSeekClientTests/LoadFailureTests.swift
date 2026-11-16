import Foundation
import Testing
import WebKit
@testable import NodeSeekClient

struct LoadFailureTests {
    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed])
    func offline(code: URLError.Code) {
        let failure = LoadFailure(URLError(code))
        #expect(failure.kind == .offline)
        #expect(failure.title == "网络未连接")
        #expect(failure.message == "网络未连接，请检查网络设置后重试。")
    }

    @Test func timeout() {
        let failure = LoadFailure(URLError(.timedOut))
        #expect(failure.kind == .timedOut)
        #expect(failure.message == "连接超时，网络较慢或 NodeSeek 响应慢，请稍后重试。")
    }

    @Test(arguments: [URLError.Code.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                      .secureConnectionFailed, .serverCertificateUntrusted])
    func unreachable(code: URLError.Code) {
        let failure = LoadFailure(URLError(code))
        #expect(failure.kind == .unreachable)
        // The account page's existing wording.
        #expect(failure.message == "无法连接 NodeSeek，请检查网络后重试。")
    }

    @Test func namesTheServiceThatFailed() {
        #expect(LoadFailure(URLError(.cannotFindHost), service: "NodeImage").title == "无法连接 NodeImage")
    }

    @Test(arguments: [500, 502, 503, 522])
    func serverErrors(status: Int) {
        let failure = LoadFailure(SiteError.httpStatus(status))
        #expect(failure.kind == .serverBusy)
        #expect(failure.title == "NodeSeek 暂时不可用")
    }

    @Test func tooManyRequests() {
        #expect(LoadFailure(SiteError.httpStatus(429)).kind == .rateLimited)
        #expect(LoadFailure(SiteError.message("请求失败 (429)")).kind == .rateLimited)
    }

    @Test func siteChecks() {
        #expect(LoadFailure(SiteError.verificationRequired).kind == .verificationRequired)
        #expect(LoadFailure(SiteError.httpStatus(403)).kind == .verificationRequired)
        #expect(LoadFailure(SiteError.message("官网未返回可读取的数据 (403)")).kind == .verificationRequired)
    }

    @Test func statusInTheScriptsOwnMessages() {
        #expect(LoadFailure(SiteError.message("请求失败 (502)")).kind == .serverBusy)
        #expect(LoadFailure(SiteError.message("图床请求失败 (503)。"), service: "NodeImage").title == "NodeImage 暂时不可用")
    }

    @Test func networkErrorsWrappedByOtherErrors() {
        let wrapped = NSError(domain: "WebKitErrorDomain", code: 102,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: -1009)])
        #expect(LoadFailure(wrapped).kind == .offline)
        #expect(LoadFailure(NSError(domain: NSURLErrorDomain, code: -1001)).kind == .timedOut)
    }

    @MainActor @Test func failedWebPageNavigation() {
        let error = WebPage.NavigationError.failedProvisionalNavigation(URLError(.cannotFindHost))
        #expect(LoadFailure(error).kind == .unreachable)
    }

    @Test func scriptMessagesBecomeURLErrors() {
        #expect(ScriptNetworkError.urlError(for: ScriptNetworkError.timedOut)?.code == .timedOut)
        #expect(ScriptNetworkError.urlError(for: ScriptNetworkError.offline)?.code == .notConnectedToInternet)
        #expect(ScriptNetworkError.urlError(for: ScriptNetworkError.unreachable)?.code == .cannotConnectToHost)
        #expect(ScriptNetworkError.urlError(for: "没有找到帖子内容") == nil)
    }

    @Test func siteWordsAreKept() {
        let failure = LoadFailure(SiteError.message("没有找到这位用户，请检查用户编号。"))
        #expect(failure.kind == .other)
        #expect(failure.message == "没有找到这位用户，请检查用户编号。")
        #expect(LoadFailure(PostAccessError.privatePost).message == "此帖仅作者可见")
    }

    @Test func systemTextNeverShows() {
        let messages = [
            LoadFailure(NSError(domain: "WebKitErrorDomain", code: 102)).message,
            LoadFailure(URLError(.cancelled)).message,
            LoadFailure(CocoaError(.fileReadUnknown)).message,
            LoadFailure(SiteError.message("undefined is not an object (evaluating 'a.b')")).message
        ]
        for message in messages {
            #expect(message == "出了点问题，请稍后重试。")
        }
    }

    @Test func connectionProblems() {
        #expect(LoadFailure(URLError(.notConnectedToInternet)).isConnectionProblem)
        #expect(!LoadFailure(SiteError.httpStatus(503)).isConnectionProblem)
    }

    @Test func displayMessageUsesTheSameWords() {
        #expect(SiteError.displayMessage(for: URLError(.notConnectedToInternet)) == "网络未连接，请检查网络设置后重试。")
    }
}
