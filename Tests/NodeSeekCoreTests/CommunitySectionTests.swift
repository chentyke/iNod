import Foundation
import Testing
@testable import NodeSeekCore

@Test func memberSearchQueryRecognizesDirectUIDsSpaceLinksAndUsernames() {
    #expect(MemberSearchQuery("   ").isEmpty)
    #expect(MemberSearchQuery("@alice_dev") == MemberSearchQuery("alice_dev"))
    #expect(MemberSearchQuery("@alice_dev").directMemberID == nil)
    #expect(MemberSearchQuery("@alice_dev").usernameQuery == "alice_dev")

    let numeric = MemberSearchQuery("9900101")
    #expect(numeric.directMemberID == 9_900_101)
    #expect(numeric.usernameQuery == "9900101")

    let prefixedUID = MemberSearchQuery("UID 9900101")
    #expect(prefixedUID.directMemberID == 9_900_101)
    #expect(prefixedUID.usernameQuery == nil)

    let hashUID = MemberSearchQuery("#9900101")
    #expect(hashUID.directMemberID == 9_900_101)
    #expect(hashUID.usernameQuery == nil)

    let spaceURL = MemberSearchQuery("https://www.nodeseek.com/space/9900101")
    #expect(spaceURL.directMemberID == 9_900_101)
    #expect(spaceURL.usernameQuery == nil)

    let externalURL = MemberSearchQuery("https://evil.test/space/9900101")
    #expect(externalURL.directMemberID == nil)
    #expect(externalURL.usernameQuery == nil)
}

@Test func searchedMemberComputesLevelAndPlainUIDMetadata() {
    let member = SearchedMember(
        member_id: 9_900_101,
        member_name: "alice_dev",
        bio: "  专注网络协议  ",
        coin: 1350
    )
    #expect(member.level == 3)
    #expect(member.trimmedBio == "专注网络协议")
    #expect(member.metadataText == "UID 9900101 · Lv 3")
    #expect(!member.metadataText.contains(","))
    #expect(member.spaceURL.absoluteString == "https://www.nodeseek.com/space/9900101")

    let unknownCoinMember = SearchedMember(member_id: 42, member_name: "guest", bio: "   ", coin: nil)
    #expect(unknownCoinMember.level == nil)
    #expect(unknownCoinMember.trimmedBio == nil)
    #expect(unknownCoinMember.metadataText == "UID 42")
}

@Test func luckyDrawParsesMarkdownLinksPostAddressesAndValidatesInputs() {
    let draw = LuckyDraw(
        postID: 301,
        revealTime: Date(timeIntervalSince1970: 1_700_000_000),
        count: 2,
        firstFloor: 3,
        removeDuplicates: true
    )
    #expect(LuckyDraw.parseInput(draw.url.absoluteString) == .draw(draw))
    #expect(LuckyDraw.parseInput(draw.markdownLink) == .draw(draw))
    #expect(LuckyDraw.parseInput("https://www.nodeseek.com/post-301-2#12") == .post(PostAddress("https://www.nodeseek.com/post-301-2#12")!))
    #expect(LuckyDraw.parseInput("301") == .post(PostAddress("301")!))
    #expect(LuckyDraw.parseInput("https://evil.test/post-301-1") == nil)

    #expect(LuckyDraw.validationMessage(postInput: "", countInput: "1", firstFloorInput: "1") == nil)
    #expect(LuckyDraw.validationMessage(postInput: "not-a-post", countInput: "1", firstFloorInput: "1") != nil)
    #expect(LuckyDraw.validationMessage(postInput: "301", countInput: "0", firstFloorInput: "1") != nil)
    #expect(LuckyDraw.validationMessage(postInput: "301", countInput: "2", firstFloorInput: "0") != nil)
    #expect(LuckyDraw.validationMessage(postInput: "301", countInput: "2", firstFloorInput: "1") == nil)

    let winners = [LuckyFloor(floor_id: 3, member_id: 101, member_name: "林风")]
    #expect(draw.winnersAnnouncement(winners).contains("post-301-1#3"))
    #expect(draw.winnersAnnouncement(winners).contains("@林风"))
    #expect(draw.winnersAnnouncement([]).isEmpty)
}

@Test func rulingRecordExtractsStructuredActionsFloorLocationsAndRecordIDs() throws {
    let json = #"""
    {
      "id": 801,
      "target_member_id": 9900201,
      "target_member_name": "推广小号",
      "admin_member_id": 9900001,
      "admin_member_name": "版务甲",
      "post_id": 301,
      "floor_index": 23,
      "request": "{\"coin\":{\"coin_diff\":-10,\"reason\":\"发布无关推广链接\"},\"hideComment\":{\"status\":true},\"suspend\":{\"status\":true,\"value\":7}}",
      "created_at": "2026-11-17T08:30:00.000Z"
    }
    """#
    let record = try JSONDecoder().decode(RulingRecord.self, from: Data(json.utf8))
    #expect(record.actionItems.map(\.kind) == [.coin, .hideComment, .suspend])
    #expect(record.description == "鸡腿 -10 · 发布无关推广链接\n隐藏内容\n禁言 7 天")

    let location = try #require(record.associatedPostLocation)
    #expect(location.post.id == 301)
    #expect(location.page == 3)
    #expect(location.floor == 23)
    #expect(record.associatedShortLabel == "帖子 #301 · #23")

    #expect(RulingRecord.parseRecordID("#801") == 801)
    #expect(RulingRecord.parseRecordID("id-801") == 801)
    #expect(RulingRecord.parseRecordID("https://www.nodeseek.com/ruling#/id-801") == 801)
    #expect(RulingRecord.parseRecordID("801") == nil)
    #expect(RulingRecord.parseRecordID("alice") == nil)
}

@Test func invitationOptionComputesAffordabilityAndShortfall() throws {
    let config = try JSONDecoder().decode(
        InvitationConfig.self,
        from: Data(#"{"payment":{"coin":{"enabled":true,"cost":1000},"stardust":{"enabled":false,"cost":100}}}"#.utf8)
    )
    #expect(config.payment.coin.canAfford(with: 1200))
    #expect(!config.payment.coin.canAfford(with: 650))
    #expect(!config.payment.coin.canAfford(with: nil))
    #expect(config.payment.coin.shortfall(for: 650) == 350)
    #expect(config.payment.coin.shortfall(for: 1000) == nil)
    #expect(!config.payment.stardust.canAfford(with: 500))

    let page = try JSONDecoder().decode(
        InvitationPage.self,
        from: Data(#"{"total":2,"data":[{"code":"A","applied":false,"created_at":""},{"code":"B","applied":true,"created_at":""}]}"#.utf8)
    )
    #expect(page.availableCount == 1)
}
