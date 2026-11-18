import Testing
@testable import NodeSeekCore

@Test func stardustRecordMapsTypesAndSanitizesIdentifiers() {
    #expect(StardustRecord.typeTitle("system") == "系统")
    #expect(StardustRecord.typeTitle("admin") == "管理")
    #expect(StardustRecord.typeTitle("transfer") == "转账")
    #expect(StardustRecord.typeTitle("upvote") == "点赞")
    #expect(StardustRecord.typeTitle("buyCode") == "购买邀请码")
    #expect(StardustRecord.typeTitle("customBonus") == "customBonus")

    let positive = StardustRecord(
        id: 1,
        diff: 1250,
        result: 2500,
        type: "transfer",
        created_at: "2026-11-17T09:30:00.000Z",
        peer_id: 9_900_001,
        ref_id: 100
    )
    #expect(positive.typeTitle == "转账")
    #expect(positive.validPeerID == 9_900_001)
    #expect(positive.validRefID == 100)
    #expect(positive.formattedDiff == "+\((1250).formatted())")

    let zeroIDs = StardustRecord(
        id: 2,
        diff: -20,
        result: 80,
        type: "buyCode",
        created_at: "2026-11-17T09:30:00.000Z",
        peer_id: 0,
        ref_id: 0
    )
    #expect(zeroIDs.validPeerID == nil)
    #expect(zeroIDs.validRefID == nil)
    #expect(zeroIDs.formattedDiff == (-20).formatted())
}

@Test func stardustFilterNormalizesPeerLinksAndReferenceDigits() throws {
    let empty = StardustFilter()
    #expect(empty.isEmpty)
    #expect(empty.isValid)
    #expect(empty.chips.isEmpty)
    #expect(empty.normalized() == StardustFilter())

    let fromLink = StardustFilter(
        type: "transfer",
        peer: " https://www.nodeseek.com/space/9900001 ",
        reference: " 002 "
    )
    #expect(fromLink.isValid)
    let normalized = try #require(fromLink.normalized())
    #expect(normalized == StardustFilter(type: "transfer", peer: "9900001", reference: "002"))
    #expect(normalized.chips.map(\.label) == ["类型：转账", "对方 UID 9900001", "Ref ID 002"])

    let afterRemovingPeer = normalized.removing(.peer("9900001"))
    #expect(afterRemovingPeer == StardustFilter(type: "transfer", peer: "", reference: "002"))

    for invalidPeer in ["0", "-5", "abc", "https://example.com/space/9"] {
        let filter = StardustFilter(peer: invalidPeer)
        #expect(!filter.isPeerValid)
        #expect(!filter.isValid)
        #expect(filter.normalized() == nil)
    }

    for invalidReference in ["0", "-1", "+5", "①", "12a"] {
        let filter = StardustFilter(reference: invalidReference)
        #expect(!filter.isReferenceValid)
        #expect(!filter.isValid)
        #expect(filter.normalized() == nil)
    }
}
