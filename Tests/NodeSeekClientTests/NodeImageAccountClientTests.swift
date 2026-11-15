import Foundation
import Testing
@testable import NodeSeekClient

private let grant = Data(#"{"success":true,"links":["https://www.nodeimage.com/"],"data":{"uid":42},"wtf":"nonce","sign":"signature"}"#.utf8)

@Test func nodeImageVerifiesGrantForTheIntendedSite() throws {
    let body = try NodeImageAccountClient.verificationBody(grant: grant)
    let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(Set(fields.keys) == ["data", "wtf", "sign"])
    #expect(fields["sign"] as? String == "signature")
    let unexpected = Data(#"{"success":true,"links":["https://www.nodeimage.com.example.org"],"data":{},"wtf":"nonce","sign":"signature"}"#.utf8)
    #expect(throws: SiteError.self) { try NodeImageAccountClient.verificationBody(grant: unexpected) }
}

@Test func nodeImageDoesNotAcceptDifferentOrUnauthenticatedAccounts() throws {
    let status = Data(#"{"isAuthenticated":true,"userId":"42"}"#.utf8)
    try NodeImageAccountClient.checkAccount(status, userID: 42)
    #expect(throws: SiteError.self) { try NodeImageAccountClient.checkAccount(status, userID: 7) }
    let signedOut = Data(#"{"isAuthenticated":false}"#.utf8)
    #expect(throws: SiteError.self) { try NodeImageAccountClient.checkAccount(signedOut, userID: 42) }
}

@Test func nodeImageRejectsMalformedKeyResponses() {
    let malformed = Data(#"{"api_key":"not a key"}"#.utf8)
    #expect(throws: SiteError.self) { try NodeImageAccountClient.readKey(malformed) }
}

@Test func nodeImageReadsOrRotatesKeyWithTheCorrespondingRequest() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NodeImageKeyTestProtocol.self]
    let client = NodeImageAccountClient(session: URLSession(configuration: configuration))
    defer { client.close() }
    try await client.authorize(grant: grant, userID: 42)
    #expect(try await client.key(regenerating: false) == String(repeating: "a", count: 64))
    #expect(try await client.key(regenerating: true) == String(repeating: "b", count: 64))
}

private final class NodeImageKeyTestProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.host() == "api.nodeimage.com" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let json: String
        switch (request.httpMethod, url.path) {
        case ("POST", "/api/auth/verify"): json = #"{"success":true}"#
        case ("GET", "/api/user/status"): json = #"{"isAuthenticated":true,"userId":42}"#
        case ("GET", "/api/user/api-key"): json = #"{"api_key":"\#(String(repeating: "a", count: 64))"}"#
        case ("POST", "/api/user/regenerate-api-key"): json = #"{"api_key":"\#(String(repeating: "b", count: 64))"}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
