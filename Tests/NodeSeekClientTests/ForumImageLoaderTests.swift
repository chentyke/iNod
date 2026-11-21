import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import NodeSeekClient

@Test func thumbnailAndFullImageOfTheSameURLKeepTheirOwnResolution() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ForumImageTestProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let loader = ForumImageLoader(session: session)
    let url = try #require(URL(string: "https://example.com/large.png"))

    let thumbnail = try await loader.load(url, size: .thumbnail)
    let full = try await loader.load(url)
    let cachedThumbnail = try await loader.load(url, size: .thumbnail)

    #expect(thumbnail.width == 240 && thumbnail.height == 180)
    #expect(full.width == 1600 && full.height == 1200)
    #expect(cachedThumbnail === thumbnail)

    let original = try await loader.originalImage(for: url)
    #expect(original.type == .png)
    let source = try #require(CGImageSourceCreateWithData(original.data as CFData, nil))
    let exported = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(exported.width == 2000 && exported.height == 1500)
}

private final class ForumImageTestProtocol: URLProtocol, @unchecked Sendable {
    private static let png: Data? = {
        guard let context = CGContext(data: nil, width: 2000, height: 1500, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(red: 0.1, green: 0.35, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1500))
        guard let image = context.makeImage() else { return nil }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? png as Data : nil
    }()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "example.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let data = Self.png,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeContentData))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

#if DEBUG
@Test func uiTestMediaUsesRecordedDataAndOnlyAllowsLoopbackForMissingImages() throws {
    let remote = try #require(URL(string: "https://cdn.example.org/image.png"))
    let local = try #require(URL(string: "http://127.0.0.1:8080/image.png"))
    let sample = Data([1, 2, 3])
    #expect(try UITestNetwork.media(for: remote, responses: [remote.absoluteString: sample]) == sample)
    #expect(throws: URLError(.resourceUnavailable)) { try UITestNetwork.media(for: remote, responses: [:]) }
    #expect(try UITestNetwork.media(for: local, responses: [:]) == nil)
}
#endif
