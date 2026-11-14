import Foundation

public enum ForumImageRequest {
    public static func make(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(NodeSeekRoute.origin.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}
