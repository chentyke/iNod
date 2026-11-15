import Foundation

public enum NodeImageAPI {
    public enum ImageFormat: String, Sendable {
        case png, jpeg

        var mimeType: String { "image/\(rawValue)" }
        var filename: String { self == .jpeg ? "image.jpg" : "image.png" }
    }

    public static let origin = URL(string: "https://api.nodeimage.com")!
    public static func validKey(_ key: String) -> Bool { key.wholeMatch(of: /[a-fA-F0-9]{32,128}/) != nil }

    public static func list(key: String) -> URLRequest { request(path: "api/v1/images", method: "GET", key: key) }

    public static func delete(id: String, key: String) -> URLRequest? {
        guard !id.isEmpty, id.wholeMatch(of: /[a-zA-Z0-9_-]+/) != nil else { return nil }
        return request(path: "api/v1/delete/" + id, method: "DELETE", key: key)
    }

    public static func upload(png: Data, key: String, boundary: String, deleteAfterDays: Int? = nil) -> URLRequest {
        upload(image: png, format: .png, key: key, boundary: boundary, deleteAfterDays: deleteAfterDays)
    }

    public static func upload(image: Data, format: ImageFormat, key: String, boundary: String, deleteAfterDays: Int? = nil) -> URLRequest {
        var request = request(path: "api/upload", method: "POST", key: key)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"\(format.filename)\"\r\nContent-Type: \(format.mimeType)\r\n\r\n".utf8)
        body.append(image)
        body.append(Data("\r\n".utf8))
        if let days = deleteAfterDays, (1...365).contains(days) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"deleteDays\"\r\n\r\n\(days)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    public static func problem(data: Data, status: Int) -> String? {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = object?["message"] as? String
        if !(200..<300).contains(status) || object?["success"] as? Bool == false {
            if let message, !message.isEmpty { return message }
            if status == 401 || status == 403 { return "图床密钥无效或没有权限，请检查 API Key。" }
            if let error = object?["error"] as? String, !error.isEmpty { return error }
            return "图床请求失败 (\(status))。"
        }
        return nil
    }

    private static func request(path: String, method: String, key: String) -> URLRequest {
        var request = URLRequest(url: origin.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        return request
    }
}
