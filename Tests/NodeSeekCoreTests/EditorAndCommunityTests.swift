import Foundation
import Testing
@testable import NodeSeekCore

@Test func editorAppendsUploadedImagesWithoutReplacingDraftText() throws {
    let first = try #require(URL(string: "https://cdn.nodeimage.com/test-first.png"))
    let second = try #require(URL(string: "https://cdn.nodeimage.com/test-second.png"))
    var draft = EditorDraft(title: "标题", content: "原有正文")
    draft.appendHostedImage(first)
    draft.appendHostedImage(second)
    #expect(draft.title == "标题")
    #expect(MarkdownBlock.parse(draft.content) == [.text("原有正文"), .image(alt: "图片", url: first), .image(alt: "图片", url: second)])
}

@Test func editorKeepsWebsiteModesAndAccountDraftsSeparate() {
    let draft = EditorDraft(title:"标题",content:"正文",category:"tech",rank:2)
    let new = draft.body(for:.newPost)
    #expect(new["mode"] as? String == "new-discussion")
    #expect(new["category"] as? String == "tech")
    #expect(new["postId"] == nil)
    let edit = draft.body(for:.editPost(postID:10,originalRank:0))
    #expect(edit["postId"] as? Int == 10)
    #expect(edit["category"] == nil)
    #expect(draft.body(for:.editComment(commentID:20))["commentId"] as? Int == 20)
    #expect(draft.body(for:.reply(postID:10))["postId"] as? Int == 10)
    #expect(EditorDraft.key(ownerID:1,mode:.reply(postID:10)) != EditorDraft.key(ownerID:2,mode:.reply(postID:10)))
    #expect(EditorDraft.key(ownerID:1,mode:.editComment(commentID:10)) != EditorDraft.key(ownerID:1,mode:.reply(postID:10)))
}

@Test func editorFeesApplyOnlyToChargedWebsiteActions() {
    let inside = EditorDraft(title:"内版",content:"内容",category:"inside")
    #expect(EditorMode.newPost.cost(for:inside) == 5)
    #expect(EditorMode.newPost.cost(for:EditorDraft(title:"公开",content:"内容")) == 0)
    let hidden = EditorDraft(title:"私有",content:"内容",rank:255)
    #expect(EditorMode.editPost(postID:1,originalRank:0).cost(for:hidden) == 10)
    #expect(EditorMode.editPost(postID:1,originalRank:255).cost(for:hidden) == 0)
    #expect(EditorMode.reply(postID:1).cost(for:inside) == 0)
    #expect(EditorDraft(content:" ").validation(for:.reply(postID:1)) != nil)
}

@Test func referencesRespectFirstPageAndQuoteEveryLine() {
    #expect(EditorDraft.replyReference(postID:123,floor:10,name:"朋友").contains("post-123-1#10"))
    #expect(EditorDraft.replyReference(postID:123,floor:11,name:"朋友").contains("post-123-2#11"))
    #expect(EditorDraft.replyReference(postID:123,floor:21,name:"朋友",quote:"第一行\n第二行").contains("> 第一行\n> 第二行"))
}

@Test func markdownSupportsDiscussionFormattingWithoutExecutingHTML() {
    #expect(MarkdownBlock.parse("> 一行\n> 二行\n\n- A\n- B\n\n---") == [.quote("一行\n二行"),.list(items:["A","B"],ordered:false),.divider])
    #expect(MarkdownBlock.parse("| A | B |\n| --- | :---: |\n| 1 | 2 |") == [.table([["A","B"],["1","2"]])])
    #expect(MarkdownBlock.parse("前面![图](https://example.com/a.png)后面") == [.text("前面"),.image(alt:"图",url:URL(string:"https://example.com/a.png")!),.text("后面")])
    #expect(MarkdownBlock.parse("nsapp://vote?id=42") == [.vote(42)])
    #expect(MarkdownBlock.parse("```\nnsapp://vote?id=42\n```") == [.code("nsapp://vote?id=42")])
    #expect(MarkdownBlock.parse("<script>alert(1)</script>") == [.text("<script>alert(1)</script>")])
}

@Test func lotteryOrderingMatchesWebsiteJavaScript() {
    #expect(LuckyDraw.order(seed:"test",count:12) == [8,11,6,10,7,1,5,4,9,2,0,3])
    #expect(LuckyDraw.order(seed:"0123456789abcdef",count:12) == [0,2,4,10,9,5,3,11,6,8,7,1])
    #expect(LuckyDraw.order(seed:"你好",count:12) == [9,8,6,10,1,4,2,0,3,7,11,5])
    #expect(LuckyDraw.order(seed:"test",count:0).isEmpty)
}

@Test func lotteryLinksRoundTripAndIgnoreDuplicateParametersSafely() throws {
    let draw = LuckyDraw(postID:123,revealTime:Date(timeIntervalSince1970:1700000000),count:3,firstFloor:5,removeDuplicates:true)
    #expect(LuckyDraw(url:draw.url) == draw)
    #expect(draw.round == 3485631)
    #expect(LuckyDraw(url:URL(string:"https://evil.test/lucky?post=1&time=1&count=1&start=1")!) == nil)
    #expect(LuckyDraw(url:URL(string:"https://www.nodeseek.com/lucky?post=1&time=nan&count=1&start=1")!) == nil)
    let floors = try JSONDecoder().decode([LuckyFloor].self,from:Data(#"[{"floor_id":0,"member_id":1,"member_name":"A"},{"floor_id":1,"member_id":2,"member_name":"B"},{"floor_id":2,"member_id":2,"member_name":"B"},{"floor_id":3,"member_id":3,"member_name":"C"}]"#.utf8))
    let selection = LuckyDraw(postID:1,revealTime:draw.revealTime,count:5).winners(floors:floors,randomness:"test")
    #expect(selection.map(\.floor_id) == [1,3])
}

@Test func votePayloadIncludesPublicParticipantsAndSelection() throws {
    let vote = try JSONDecoder().decode(VoteResponse.self,from:Data(#"{"success":true,"vote":{"id":42,"title":"问题","uid":1,"isPublic":true,"locked":false,"multiple":true,"items":[{"vote_item_id":100,"text":"A","count":2,"voted":true,"voters":[1,2]},{"vote_item_id":101,"text":"B","count":1,"voted":false,"voters":[3]}]}}"#.utf8)).vote
    #expect(vote.hasVoted)
    #expect(vote.total == 3)
    #expect(vote.items.first?.voters == [1,2])
}

@Test func websiteFlagsAcceptSQLAndJSONValuesAndRejectUnknownNumbers() throws {
    let d = JSONDecoder()
    #expect(try d.decode(WebsiteFlag.self,from:Data("1".utf8)).wrappedValue == true)
    #expect(try d.decode(WebsiteFlag.self,from:Data("false".utf8)).wrappedValue == false)
    #expect(try d.decode(WebsiteFlag.self,from:Data("null".utf8)).wrappedValue == nil)
    #expect(throws:(any Error).self) { try d.decode(WebsiteFlag.self,from:Data("2".utf8)) }
}

@Test func stardustLinksKeepRecipientAmountAndDescriptionSeparate() throws {
    let request = StardustRequest(memberID:9,reference:123,amount:5,description:"C++ & 支持",once:true)
    #expect(StardustRequest(request.link) == request)
    #expect(StardustRequest("nsapp://stardust-receive?member_id=9&ref_id=1&diff=-1") == nil)
    #expect(MarkdownBlock.parse(request.link) == [.stardust(request)])
    #expect(MarkdownBlock.parse("前文 nsapp://vote?id=42 后文") == [.text("前文"),.vote(42),.text("后文")])
    #expect(MarkdownBlock.parse("[支付](\(request.link))") == [.stardust(request)])
}

@Test func votesWithoutPermissionToSeeCountsKeepStatsUnknown() throws {
    let vote = try JSONDecoder().decode(VoteResponse.self,from:Data(#"{"success":true,"vote":{"id":456,"title":"公开问题","uid":9,"isPublic":true,"locked":false,"multiple":false,"items":[{"vote_item_id":1,"text":"A","voted":false},{"vote_item_id":2,"text":"B","voted":false}]}}"#.utf8)).vote
    #expect(!vote.hasVoted)
    #expect(vote.total == nil)
    #expect(vote.items.first?.count == nil)
    #expect(vote.items.first?.voters == nil)
}
