import Foundation
import NodeSeekCore
import Testing
@testable import NodeSeekClient

@MainActor
@Test func nodeImageHistoryKeepsListsWithTheirAccountAndCredential() {
    let history = NodeImageHistory()
    history.store([], userID: 101, key: "first")
    #expect(history.cachedImages(userID: 101, key: "first")?.isEmpty == true)
    #expect(history.cachedImages(userID: 102, key: "first") == nil)
    #expect(history.cachedImages(userID: 101, key: "second") == nil)
    history.reset()
    #expect(history.cachedImages(userID: 101, key: "first") == nil)
}

@MainActor
@Test func nodeImageHistoryRecordsUploadedImagesOnceInTheMatchingList() throws {
    let history = NodeImageHistory()
    let older = try JSONDecoder().decode(HostedImage.self, from: Data(#"{"imageId":"old","url":"https://cdn.nodeimage.com/test-old.png"}"#.utf8))
    let uploaded = try JSONDecoder().decode(HostedImage.self, from: Data(#"{"imageId":"new","url":"https://cdn.nodeimage.com/test-new.png"}"#.utf8))
    history.store([older], userID: 101, key: "first")
    history.recordUpload(uploaded, userID: 102, key: "first")
    #expect(history.cachedImages(userID: 101, key: "first")?.map(\.id) == ["old"])
    history.recordUpload(uploaded, userID: 101, key: "first")
    history.recordUpload(uploaded, userID: 101, key: "first")
    #expect(history.cachedImages(userID: 101, key: "first")?.map(\.id) == ["new", "old"])
}

@MainActor
@Test func nodeImageHistoryRefreshKeepsUploadsThatFinishWhileItLoads() throws {
    let history = NodeImageHistory()
    let older = try JSONDecoder().decode(HostedImage.self, from: Data(#"{"imageId":"old","url":"https://cdn.nodeimage.com/test-old.png"}"#.utf8))
    let first = try JSONDecoder().decode(HostedImage.self, from: Data(#"{"imageId":"first","url":"https://cdn.nodeimage.com/test-first.png"}"#.utf8))
    let second = try JSONDecoder().decode(HostedImage.self, from: Data(#"{"imageId":"second","url":"https://cdn.nodeimage.com/test-second.png"}"#.utf8))
    let refreshed = history.finishRefresh([first, older], recentUploads: [first, second], userID: 101, key: "first")
    #expect(refreshed.map(\.id) == ["second", "first", "old"])
    #expect(history.cachedImages(userID: 101, key: "first")?.map(\.id) == ["second", "first", "old"])
}

@Test func nodeImageClientFixtureValidatesKeyAndDecodesImages() async throws {
    let validKey = String(repeating: "a", count: 64)
    let listJSON = Data(#"{"images":[{"image_id":"img_1","filename":"chart.png","url":"https://cdn.nodeimage.com/i/chart.png"}]}"#.utf8)
    let client = NodeImageClient(responsesForUITests: [
        "https://api.nodeimage.com/api/v1/images": listJSON
    ])
    await #expect(throws: SiteError.self) {
        _ = try await client.images(key: "invalid")
    }
    let images = try await client.images(key: validKey)
    #expect(images.count == 1)
    #expect(images.first?.filename == "chart.png")
    try await client.delete(images[0], key: validKey)
}
