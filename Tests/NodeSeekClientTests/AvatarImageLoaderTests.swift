#if canImport(AppKit)
import AppKit
#endif
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import NodeSeekClient

private final class RequestCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL: Int] = [:]
    private var requests: [URL: URLRequest] = [:]
    func record(_ request: URLRequest, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        values[url, default: 0] += 1
        requests[url] = request
    }
    func request(_ url: URL) -> URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests[url]
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
        Self.counts.record(request, for: url)
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

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct AvatarImageLoaderTests {
    @Test func concurrentLoadsShareTheCachedImageAndChangingTheURLFetchesAgain() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let loader = AvatarImageLoader(session: session)
        let url = try #require(URL(string: "https://avatar-cache.test/avatar/1.png"))
        async let first = loader.load(url)
        async let second = loader.load(url)
        let (one, two) = try await (first, second)
        #expect(one === two)
        #expect(loader.image(for: url) === one)
        let again = try await loader.load(url)
        #expect(again === one)
        #expect(AvatarProtocol.counts.count(url) == 1)
        let request = try #require(AvatarProtocol.counts.request(url))
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

        let updated = try #require(URL(string: "https://avatar-cache.test/avatar/1.png?v=2"))
        #expect(loader.image(for: updated) == nil)
        let newImage = try await loader.load(updated)
        #expect(newImage !== one)
        #expect(AvatarProtocol.counts.count(updated) == 1)
        #expect(loader.image(for: updated) === newImage)
    }

    @Test func cancellingAViewLeavesItsDownloadInTheCache() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let loader = AvatarImageLoader(session: session)
        let url = try #require(URL(string: "https://avatar-cache.test/avatar/slow.png"))
        let disappearingView = Task { try await loader.load(url) }
        for _ in 0..<100 {
            if AvatarProtocol.counts.count(url) > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(AvatarProtocol.counts.count(url) == 1)
        disappearingView.cancel()
        let image = try await disappearingView.value
        #expect(loader.image(for: url) === image)
        let cached = try await loader.load(url)
        #expect(cached === image)
        #expect(AvatarProtocol.counts.count(url) == 1)
    }

    @Test func failedImagesAreNotRequestedAgainOnTheNextLoad() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let loader = AvatarImageLoader(session: session)
        let url = try #require(URL(string: "https://avatar-cache.test/avatar/failure.png"))
        for _ in 0..<2 {
            await #expect(throws: SiteError.self) { _ = try await loader.load(url) }
        }
        #expect(loader.image(for: url) == nil)
        #expect(AvatarProtocol.counts.count(url) == 1)
    }

    @Test func svgServedAtAPNGAddressIsRasterizedAndCachedAtThumbnailSize() async throws {
        #if canImport(AppKit)
        _ = NSApplication.shared
        #endif
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let loader = AvatarImageLoader(session: session)
        let url = try #require(URL(string: "https://avatar-cache.test/avatar/default.png"))
        let thumbnail = try await loader.load(url)
        #expect(thumbnail.width == 384 && thumbnail.height == 192)
        #expect(loader.image(for: url) === thumbnail)
        #expect(AvatarProtocol.counts.count(url) == 1)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvatarProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}
