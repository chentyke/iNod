import Foundation
import Testing
@testable import NodeSeekCore

@Test func memberAddressAcceptsOnlyOfficialProfilesAndPositiveIDs() {
    for value in ["9", "  9\n", "https://www.nodeseek.com/space/9", "https://nodeseek.com/space/9/?from=app#comments"] {
        #expect(MemberAddress.parse(value) == 9)
    }
    for value in ["", "0", "-9", "9.0", "９", "https://evil.example/space/9", "http://www.nodeseek.com/space/9", "https://www.nodeseek.com.evil.example/space/9", "https://user@www.nodeseek.com/space/9", "https://www.nodeseek.com:8443/space/9", "https://www.nodeseek.com/post-9-1", "https://www.nodeseek.com/space/9/edit", "999999999999999999999999999999"] {
        #expect(MemberAddress.parse(value) == nil)
    }
}

@Test func profileHasViewerSpecificFollowStateWithoutRequiringPrivateFields() throws {
    let profile = try JSONDecoder().decode(AccountProfile.self, from: Data(#"{"id":9,"name":"example","followed":true,"topics":3,"fans":4}"#.utf8))
    #expect(profile.followed == true)
    #expect(profile.readme == nil)
    #expect(profile.coins == nil)
    #expect(profile.level == nil)
    #expect(profile.recipient.profileURL.absoluteString == "https://www.nodeseek.com/space/9")
    let guest = try JSONDecoder().decode(AccountProfile.self, from: Data(#"{"id":9,"name":"example"}"#.utf8))
    #expect(guest.followed == nil)
}

@Test func conversationRejectsWrongRecipientsAndUnrelatedPrivateMessages() throws {
    let json = #"{"peer":{"id":9,"name":"example"},"items":[{"id":1,"senderID":12,"receiverID":9,"content":"hello","createdAt":"2026-10-15T13:00:00Z","isMarkdown":false,"viewed":true},{"id":2,"senderID":9,"receiverID":12,"content":"**reply**","createdAt":"2026-10-15T13:00:01Z","isMarkdown":true,"viewed":false}]}"#
    let conversation = try JSONDecoder().decode(ConversationData.self, from: Data(json.utf8))
    #expect(conversation.belongs(to: 12, peerID: 9))
    #expect(!conversation.belongs(to: 13, peerID: 9))
    #expect(!conversation.belongs(to: 12, peerID: 10))
    #expect(!conversation.belongs(to: 9, peerID: 9))
    #expect(!conversation.belongs(to: 0, peerID: 9))
    #expect(conversation.items[1].isMarkdown)
    #expect(!conversation.items[1].viewed)
    let empty = try JSONDecoder().decode(ConversationData.self, from: Data(#"{"peer":{"id":9,"name":"example"},"items":[]}"#.utf8))
    #expect(empty.belongs(to: 12, peerID: 9))
}

@Test func privateDraftsKeepMarkdownAndSeparateAccountAndRecipient() throws {
    let draft = MessageDraft(content: "**未发出的草稿** :xhj003:", isMarkdown: true)
    #expect(try JSONDecoder().decode(MessageDraft.self, from: JSONEncoder().encode(draft)) == draft)
    #expect(MessageDraft.key(ownerID: 12, peerID: 9) != MessageDraft.key(ownerID: 13, peerID: 9))
    #expect(MessageDraft.key(ownerID: 12, peerID: 9) != MessageDraft.key(ownerID: 12, peerID: 10))
    #expect(MessageDraft.key(ownerID: 12, peerID: 9) != MessageDraft.key(ownerID: 9, peerID: 12))
}
