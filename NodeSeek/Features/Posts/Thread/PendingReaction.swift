import NodeSeekCore

struct PendingReaction {
    let commentID: Int
    let reaction: CommentReaction
    let cost: Int
    let accountRevision: Int

    var message: String {
        let fee = cost == 0 ? "本次使用免费投喂次数。" : "本次消耗 \(cost) 个鸡腿。"
        return fee + "提交后不能撤回。"
    }
}
