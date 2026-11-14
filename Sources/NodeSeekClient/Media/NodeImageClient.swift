import NodeSeekCore
import Foundation

public actor NodeImageClient {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NodeImageRedirects(), delegateQueue: nil)
    }

    public func images(key: String) async throws -> [HostedImage] {
        let data = try await send(NodeImageAPI.list(key: key))
        let images = try JSONDecoder().decode(HostedImageList.self, from: data).images
        guard images.allSatisfy({ !$0.id.isEmpty }), Set(images.map(\.id)).count == images.count else { throw SiteError.message("图床返回了无法识别的图片列表。") }
        return images
    }

    public func upload(png: Data, key: String) async throws -> HostedImage {
        let data = try await send(NodeImageAPI.upload(png: png, key: key, boundary: UUID().uuidString))
        do { return try JSONDecoder().decode(HostedImage.self, from: data) }
        catch { throw SiteError.message("图床没有返回可用的图片地址。图片可能已经上传，请刷新已上传列表检查，避免重复上传。") }
    }

    public func delete(_ image: HostedImage, key: String) async throws {
        guard let request = NodeImageAPI.delete(id: image.id, key: key) else { throw SiteError.invalidResponse }
        _ = try await send(request, allowsMissing: true)
    }

    private func send(_ request: URLRequest, allowsMissing: Bool = false) async throws -> Data {
        guard let key = request.value(forHTTPHeaderField: "X-API-Key"), NodeImageAPI.validKey(key) else { throw SiteError.message("请先填写有效的 NodeImage API Key。") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SiteError.invalidResponse }
        if allowsMissing, http.statusCode == 404 { return data }
        if let problem = NodeImageAPI.problem(data: data, status: http.statusCode) { throw SiteError.message(problem) }
        if !(allowsMissing && http.statusCode == 204), (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] == nil {
            throw SiteError.message("图床没有返回可读取的数据，请刷新列表检查结果。")
        }
        return data
    }
}

private final class NodeImageRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host() == "api.nodeimage.com" ? request : nil)
    }
}
