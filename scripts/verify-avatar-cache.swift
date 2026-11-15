import Foundation
import ImageIO
import UniformTypeIdentifiers

private final class RequestCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL: Int] = [:]
    func record(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        values[url, default: 0] += 1
    }
    func count(_ url: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return values[url, default: 0]
    }
}

private final class AvatarProtocol: URLProtocol, @unchecked Sendable {
    static let counts = RequestCounts()
    static let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="512" viewBox="0 0 1024 512">
          <rect width="1024" height="512" fill="red"/>
        </svg>
        """.utf8)
    static let png: Data = {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "avatar-cache.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.counts.record(url)
        precondition(request.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [self] in
            let status = url.path.contains("failure") ? 404 : 200
            let isSVG = url.lastPathComponent == "default.png"
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": isSVG ? "image/svg+xml" : "image/png",
                                                          "Cache-Control": "no-store"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: isSVG ? Self.svg : Self.png)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { }
}

@main private struct AvatarCacheChecks {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvatarProtocol.self]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = AvatarImageLoader(session: session)
        let url = URL(string: "https://avatar-cache.test/avatar/1.png")!

        async let first = loader.load(url)
        async let second = loader.load(url)
        let (one, two) = try await (first, second)
        precondition(one === two && AvatarProtocol.counts.count(url) == 1)
        precondition(loader.image(for: url) === one)
        let again = try await loader.load(url)
        precondition(again === one && AvatarProtocol.counts.count(url) == 1)
        print("PASS: concurrent and repeated views share one request and one decoded image")

        let updated = URL(string: "https://avatar-cache.test/avatar/1.png?v=2")!
        precondition(loader.image(for: updated) == nil)
        _ = try await loader.load(updated)
        precondition(AvatarProtocol.counts.count(updated) == 1 && loader.image(for: updated) != nil)
        print("PASS: changed avatar URLs fetch a new image immediately")

        let slow = URL(string: "https://avatar-cache.test/avatar/slow.png")!
        let disappearingView = Task { try await loader.load(slow) }
        for _ in 0..<100 {
            if AvatarProtocol.counts.count(slow) > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        precondition(AvatarProtocol.counts.count(slow) == 1)
        disappearingView.cancel()
        _ = try await disappearingView.value
        precondition(loader.image(for: slow) != nil)
        _ = try await loader.load(slow)
        precondition(AvatarProtocol.counts.count(slow) == 1)
        print("PASS: scrolling a view away does not discard its shared download")

        let failure = URL(string: "https://avatar-cache.test/avatar/failure.png")!
        for _ in 0..<2 {
            do { _ = try await loader.load(failure); preconditionFailure("HTTP errors must not become avatars") }
            catch { }
        }
        precondition(loader.image(for: failure) == nil && AvatarProtocol.counts.count(failure) == 1)
        print("PASS: failed images stay placeholders and do not retry on every row reuse")

        let defaultAvatar = URL(string: "https://avatar-cache.test/avatar/default.png")!
        let thumbnail = try await loader.load(defaultAvatar)
        precondition(thumbnail.width == 384 && thumbnail.height == 192)
        precondition(loader.image(for: defaultAvatar) === thumbnail)
        print("PASS: an SVG served at a .png avatar URL is rendered at the thumbnail size and cached")
    }
}
