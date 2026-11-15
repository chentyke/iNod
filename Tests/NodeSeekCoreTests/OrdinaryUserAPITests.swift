import Foundation
import Testing
@testable import NodeSeekCore

@Test func categoriesReadServerNamesAndPublicationPermissions() throws {
    let json = #"{"success":true,"data":[{"key":"tech","cn_text":"技术新名称"},{"key":"new-board","cn_text":"新增版块","adminOnly":1}]}"#
    let response = try JSONDecoder().decode(CategoryResponse.self, from: Data(json.utf8))
    #expect(response.data.map(\.title) == ["技术新名称", "新增版块"])
    #expect(response.data[0].symbol == "chevron.left.forwardslash.chevron.right")
    #expect(!response.data[0].adminOnly && response.data[1].adminOnly)
    #expect(response.data[1].symbol == "bubble.left.and.bubble.right")
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ForumCategory.self, from: Data(#"{"key":"../setting","cn_text":"错误"}"#.utf8))
    }
}

@Test func signInSuccessCanStillRequireASecondFactor() throws {
    let response = try JSONDecoder().decode(SignInResponse.self, from: Data(#"{"success":true,"need2FA":true,"otpSession":"example-session"}"#.utf8))
    #expect(response.success && response.need2FA == true)
    #expect(response.otpSession == "example-session")
    let expired = try JSONDecoder().decode(SignInResponse.self, from: Data(#"{"success":false,"message":"OTP_EXPIRED_OR_NOT_EXIST"}"#.utf8))
    #expect(expired.isExpired && !expired.success)
    let signedIn = try JSONDecoder().decode(SignInResponse.self, from: Data(#"{"success":true}"#.utf8))
    #expect(signedIn.need2FA == nil)
}

@Test func nodeImageReadsBothDocumentedUploadAnswers() throws {
    for json in [#"{"success":true,"image_id":"abc123","filename":"image.webp","links":{"direct":"https://cdn.nodeimage.com/i/abc123.webp"}}"#, #"{"imageId":"abc123","url":"https://cdn.nodeimage.com/i/abc123.webp"}"#] {
        let image = try JSONDecoder().decode(HostedImage.self, from: Data(json.utf8))
        #expect(image.id == "abc123")
        #expect(image.url.host() == "cdn.nodeimage.com")
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HostedImage.self, from: Data(#"{"success":true,"image_id":"abc123"}"#.utf8))
    }
}

@Test func nodeImageUsesItsOwnKeyAndVersionedManagementRoutes() throws {
    let key = String(repeating: "a", count: 64)
    #expect(NodeImageAPI.validKey(key))
    #expect(!NodeImageAPI.validKey("invalid key"))
    let list = NodeImageAPI.list(key: key)
    #expect(list.url?.absoluteString == "https://api.nodeimage.com/api/v1/images")
    #expect(list.value(forHTTPHeaderField: "X-API-Key") == key)
    #expect(!list.httpShouldHandleCookies)
    #expect(list.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(list.value(forHTTPHeaderField: "Authorization") == nil)
    let deletion = try #require(NodeImageAPI.delete(id: "abc123", key: key))
    #expect(deletion.httpMethod == "DELETE")
    #expect(deletion.url?.path == "/api/v1/delete/abc123")
    #expect(NodeImageAPI.delete(id: "../account", key: key) == nil)
    let upload = NodeImageAPI.upload(png: Data([0, 1, 2]), key: key, boundary: "test-boundary")
    #expect(upload.httpMethod == "POST")
    #expect(upload.url?.path == "/api/upload")
    let body = String(decoding: try #require(upload.httpBody), as: UTF8.self)
    #expect(body.contains("name=\"image\"; filename=\"image.png\""))
    #expect(body.hasSuffix("\r\n--test-boundary--\r\n"))
    #expect(!body.contains("deleteDays"))
    let expiring = NodeImageAPI.upload(png: Data([0, 1, 2]), key: key, boundary: "test-boundary", deleteAfterDays: 30)
    let expiringBody = String(decoding: try #require(expiring.httpBody), as: UTF8.self)
    #expect(expiringBody.contains("name=\"deleteDays\"\r\n\r\n30\r\n--test-boundary--"))
    for days in [0, 366] {
        let upload = NodeImageAPI.upload(png: Data(), key: key, boundary: "test-boundary", deleteAfterDays: days)
        let body = String(decoding: try #require(upload.httpBody), as: UTF8.self)
        #expect(!body.contains("deleteDays"))
    }
    let compressed = NodeImageAPI.upload(image: Data(), format: .jpeg, key: key, boundary: "test-boundary")
    let compressedBody = String(decoding: try #require(compressed.httpBody), as: UTF8.self)
    #expect(compressedBody.contains("filename=\"image.jpg\"\r\nContent-Type: image/jpeg"))
    #expect(NodeImageAPI.problem(data: Data(#"{"success":false,"message":"配额不足"}"#.utf8), status: 200) == "配额不足")
    #expect(NodeImageAPI.problem(data: Data(#"{"error":"配额不足"}"#.utf8), status: 429) == "配额不足")
    #expect(NodeImageAPI.problem(data: Data(), status: 401)?.contains("密钥") == true)
}

@Test func nodeImageFormatsLinksForCopyingAndEmbedding() throws {
    let url = try #require(URL(string: "https://cdn.nodeimage.com/i/example.webp?a=1&b=2"))
    #expect(HostedImageLinkFormat.direct.text(for: url) == url.absoluteString)
    #expect(HostedImageLinkFormat.bbcode.text(for: url) == "[img]\(url.absoluteString)[/img]")
    #expect(HostedImageLinkFormat.html.text(for: url).contains("?a=1&amp;b=2"))
    #expect(MarkdownBlock.parse(HostedImageLinkFormat.markdown.text(for: url)) == [.image(alt: "图片", url: url)])
}

@Test func telegramReadsBindingDetailWithoutInventingMissingNames() throws {
    let response = try JSONDecoder().decode(TelegramAccountResponse.self, from: Data(#"{"success":true,"telegramDetail":{"first_name":"Example","last_name":"User"}}"#.utf8))
    #expect(response.telegramDetail?.displayName == "Example User")
    #expect(response.telegramDetail?.username == nil)
}
