import Foundation
import NodeSeekCore

@MainActor
extension AccountSession {
    public func syncNodeImageKey(userID: Int, regenerating: Bool = false) async throws -> String {
        guard signInStatus == .signedIn, user?.id == userID else {
            throw SiteError.message("请先登录当前论坛账号。")
        }
        guard !isSyncingNodeImageKey else { throw SiteError.message("正在处理 NodeImage 密钥，请稍后重试。") }
        isSyncingNodeImageKey = true
        defer { isSyncingNodeImageKey = false }
        let originalRevision = revision
        #if DEBUG
        if let responses = website.responsesForUITests {
            let endpoint = regenerating
                ? "POST https://api.nodeimage.com/api/user/regenerate-api-key"
                : "https://api.nodeimage.com/api/user/api-key"
            guard let data = responses[endpoint] ?? responses["https://api.nodeimage.com/api/user/api-key"] else {
                throw SiteError.message("论坛没有返回可用的 NodeImage 授权。请确认论坛已登录后重试。")
            }
            let key = try NodeImageAccountClient.readKey(data)
            try NodeImageKeyStore.save(key, userID: userID)
            return key
        }
        #endif
        let grant = try await website.reader.nodeImageGrant(userID: userID)
        let nodeImage = NodeImageAccountClient()
        defer { nodeImage.close() }
        try await nodeImage.authorize(grant: grant, userID: userID)
        try Task.checkCancellation()
        guard revision == originalRevision, signInStatus == .signedIn, user?.id == userID else {
            throw SiteError.message("论坛登录账号已变化，请重新打开图片页。")
        }
        let key = try await nodeImage.key(regenerating: regenerating)
        do { try NodeImageKeyStore.save(key, userID: userID) }
        catch where regenerating {
            throw SiteError.message("密钥已更新，本机保存失败。请重新同步密钥。")
        }
        return key
    }
}

struct NodeImageAccountClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            // A fresh, in-memory cookie jar carries only this NodeImage authorization.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
            self.session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        }
    }

    func close() { session.finishTasksAndInvalidate() }

    func authorize(grant data: Data, userID: Int) async throws {
        let payload = try Self.verificationBody(grant: data)
        _ = try await request("api/auth/verify", method: "POST", body: payload)
        let status = try await request("api/user/status")
        try Self.checkAccount(status, userID: userID)
    }

    func key(regenerating: Bool) async throws -> String {
        if !regenerating { return try await currentKey() }
        do {
            return try Self.readKey(await request("api/user/regenerate-api-key", method: "POST"))
        } catch {
            // A lost response may follow a successful rotation. The sync action reads the current key.
            throw SiteError.message("无法确认密钥是否已更新。请先同步密钥，再决定是否重新更新。")
        }
    }

    private func currentKey() async throws -> String {
        try Self.readKey(await request("api/user/api-key"))
    }

    static func verificationBody(grant: Data) throws -> Data {
        guard let response = try JSONSerialization.jsonObject(with: grant) as? [String: Any],
              response["success"] as? Bool == true,
              let links = response["links"] as? [String], links.contains(where: { link in
                  guard let url = URL(string: link) else { return false }
                  return url.scheme == "https" && url.host() == "www.nodeimage.com" && (url.port == nil || url.port == 443)
              }),
              let data = response["data"], !(data is NSNull),
              let wtf = response["wtf"], !(wtf is NSNull),
              let signature = response["sign"] as? String, !signature.isEmpty else {
            throw SiteError.message("论坛没有返回可用的 NodeImage 授权。请确认论坛已登录后重试。")
        }
        return try JSONSerialization.data(withJSONObject: ["data": data, "wtf": wtf, "sign": signature])
    }

    static func checkAccount(_ data: Data, userID: Int) throws {
        let status = try JSONDecoder().decode(Status.self, from: data)
        guard status.isAuthenticated else { throw SiteError.message("NodeImage 授权已失效，请重试。") }
        guard status.userId == userID else { throw SiteError.message("NodeImage 与当前论坛账号不一致。") }
    }

    static func readKey(_ data: Data) throws -> String {
        let result = try JSONDecoder().decode(Key.self, from: data)
        guard NodeImageAPI.validKey(result.api_key) else { throw SiteError.message("NodeImage 没有返回可用的密钥。") }
        return result.api_key
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: NodeImageAPI.origin.appending(path: path))
        request.mainDocumentURL = NodeImageAPI.origin
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.nodeimage.com", forHTTPHeaderField: "Origin")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SiteError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw SiteError.message("NodeImage 没有接受本次授权，请确认论坛已登录后重试。")
        }
        if let problem = NodeImageAPI.problem(data: data, status: http.statusCode) { throw SiteError.message(problem) }
        return data
    }

    private struct Key: Decodable {
        let api_key: String
    }

    private struct Status: Decodable {
        let isAuthenticated: Bool
        let userId: Int?

        private enum CodingKeys: CodingKey { case isAuthenticated, userId }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            isAuthenticated = try values.decode(Bool.self, forKey: .isAuthenticated)
            if let id = try? values.decode(Int.self, forKey: .userId) {
                userId = id
            } else {
                userId = (try? values.decode(String.self, forKey: .userId)).flatMap(Int.init)
            }
        }
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
