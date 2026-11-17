# 官网接口记录

接口格式来自 NodeSeek 官网页面和公开 JavaScript，可能随官网更新。

## 已接入

| 用途 | 请求 | 参数 / 数据 |
| --- | --- | --- |
| 首页 | `GET /`、`GET /page-{page}` | `sortBy=replyTime` 或 `postTime` |
| 版块 | `GET /categories/{key}`、`/categories/{key}/page-{page}` | 同上 |
| 搜索 | `GET /search` | `q`、`page`、`sortBy`、可选 `category` |
| 详情 | `GET /post-{postId}-{page}` | `__config__.postData` |
| 回复 | `POST /api/content/new-comment` | JSON 见下文 |
| 登录状态 | `GET /` 中的 `__config__.user` | 账号编号、名称、coin、stardust、nPost、nComment 等 |
| 点赞 | `POST /api/statistics/upvote` | `{commentId, action:"add"}` |
| 免费鸡腿次数 | `GET /api/progress/today?scope=freelike` | `maxFreeLike`、`freeLikeUsed` |
| 投喂 / 反对 | `POST /api/statistics/like` 或 `/dislike` | `{commentId, action:"add"}` |

列表读取 `.post-list-item` 中的标题、作者、头像、浏览量、回复数和最近活动时间。`__config__.rotateTopics` 中的轮播帖和列表里标为置顶的帖子合在同一条轮播里，官网轮播帖排在前面，重复的帖子只显示一次。「显示已屏蔽内容」同时适用于普通列表和置顶轮播。分页读取 `[aria-label="pagination"]` 中的链接。

详情字段：`postId`、`postPage`、`postPageCount`、`title`、`categoryWord`、`views`、`collectionCount`、`op`、`comments`。`views` 可能是字符串。每条评论包括 `commentId`、`floorIndex`、`poster`、`time`、`markdown`、互动数量以及屏蔽状态。

回复请求：

```http
POST /api/content/new-comment
Content-Type: application/json
csrf-token: <官网编辑器生成的 16 字符随机值>
```

```json
{"content":"用户输入的 Markdown","mode":"new-comment","postId":123}
```

官网根据 `success` 判断结果，失败信息放在 `message` 中。客户端通过当前官网会话发送，且发送前检查页面域名。

## 其他接口

| 用途 | 请求 | 官网使用的格式 |
| --- | --- | --- |
| 用户资料 | `GET /api/account/getInfo/{uid}` | `{success, detail}` |
| 未读通知 | `GET /api/notification/unread-count` | `{success, unreadCount}` |
| 收藏同步 | `POST /api/statistics/collection` | `{postId, action:"add"或"remove"}` |
| 关注 / 取消关注 | `POST /api/fans/add` 或 `/del` | `{followed_member_id}` |
| 退出登录 | `POST /api/account/signOut` | header `x-csrf-challenge: simple-token` |
| 发帖 | `POST /api/content/new-discussion` | `{content,mode:"new-discussion",title,category,rank}`，header `csrf-token` |

官网来源：

- [首页](https://www.nodeseek.com/)
- [首页脚本](https://www.nodeseek.com/static/js/index.e7a0cd16cd39c52c71e8.js)
- [编辑器脚本](https://www.nodeseek.com/assets/markdownEditor-DE42L09T.js)

脚本文件名随官网版本更新。[帖子详情测试样本](../Tests/NodeSeekCoreTests/Fixtures/thread.json)使用虚构的用户和帖子数据。

## 表情资源

官网编辑器的资源表提供 149 个 AC娘、22 个洋葱头、32 个小黄鸡和 49 个 Fluent 表情。代码由组名与文件编号组成，例如 `:xhj003:` 对应 `/static/image/sticker/xhj/003.png`。扩展名按官网清单确定，不能统一假设为 PNG。

Fluent 使用 `/static/image/sticker/emoji/{编号}.mov`，官网另提供 WebM。客户端原生解码 PNG、GIF 和 MOV，表情与文字在同一段中排版；打开系统“减少动态效果”时显示静态帧。代码段、链接和未知代码保留原文。

## 登录与鸡腿

所有 WebPage 明确使用 `WKWebsiteDataStore.default()`，保留已有 Cookie。全 App 共用 AccountSession，官网页面加载完成或关闭后读取账号；请求失败时保留上次读取的资料并显示错误。只读取白名单中的账号字段，不提取 Cookie 或密码。登录状态只在内存中保存，每次启动重新向官网确认。

鸡腿与点赞读取每条评论的 `liked`、`disliked`、`upvoted` 及对应数量。已做过的操作不可再次点击。投喂免费额度不足时消耗 1 个鸡腿，反对消耗 2 个；按官网规则不可撤回。提交前显示费用，再查询一次免费额度，若费用上升则重新请求用户确认。成功时使用接口返回的 `current` 和 `coin`，不自行加减。失败时显示官网错误，不自动重发。

等级由 coin 按官网算法计算：达到 `100 × 等级²`，最高 6 级；账号的 rank 字段不是这里显示的等级。通知、个人内容、鸡腿与星尘明细、签到、个人主页与账号设置现已使用原生页面。登录及网站验证仍使用系统 WebKit。

## 原生账号页面

| 页面 | 官网接口 |
| --- | --- |
| 我的主题 | `GET /api/content/list-discussions?uid={id}&page={page}` |
| 我的回复 | `GET /api/content/list-comments?uid={id}&page={page}` |
| 站内收藏 | `GET /api/statistics/list-collection?page={page}` |
| 回复 / @我 | `GET /api/notification/reply-to-me/list`、`/at-me/list` |
| 私信列表 | `GET /api/notification/message/list` |
| 私信内容 | `GET /api/notification/message/with/{uid}` |
| 鸡腿明细 | `GET /api/account/credit/page-{page}` |
| 星尘明细 | `GET /api/stardust/list?member_id={id}&count=10&before_id={cursor}` |
| 签到 | `GET /api/attendance/board?page={page}` |
| 公开个人主页 | `GET /api/account/getInfo/{uid}?readme=1` |
| 编辑自己的资料 | `GET /api/account/getInfo/{uid}?readme=1&signature=1` |
| 登录安全 | `GET /api/account/otp-status`、`/api/account/signIn-history` |
| 屏蔽用户 | `GET /api/block-list/list` |
| 首页版块 | `GET /api/homepage` |

主题、回复、收藏每页 15 项；回复楼层 0–10 在第一页，此后每 10 层一页。鸡腿账簿数据是 `[变动, 余额, 理由, 时间]`，每页 20 项且官网最多显示 100 页。星尘使用接口返回的 cursor，不能使用页码代替。签到榜每页 50 人，`record:null` 表示今天未签到，不能与获得 0 奖励混淆。

用户操作用到的写入接口如下。

- 通知已读：`POST /api/notification/reply-to-me/markViewed`，`{replys:[id]}`；@我对应 `/at-me/markViewed`，`{atMe:[id]}`；全部已读附加 `?all=true`。
- 私信已读：`POST /api/notification/message/markViewed`，`{messages:[id]}`；发送：`POST /api/notification/message/send`，`{receiverUid,content,markdown:false}`。
- 签到：`POST /api/attendance?random=false` 固定 5 个鸡腿，`random=true` 随机奖励；以响应的 current 和再次读取的 record 为准。
- 编辑资料：`POST /api/account/introduction`，`{bio,signature,readme}`。
- 首页版块：`POST /api/homepage`，`{data:[{category,showInIndex}]}`。
- 屏蔽 / 解除：`POST /api/block-list/add`，`{block_member_name}`；`POST /api/block-list/del`，`{block_member_id}`。
- 退出登录：使用官网 signOut 接口，随后重新读取首页，只有官网确认未登录才清除 App 内账号显示。账号变化后重建「我的」导航，避免继续显示上一个账号的私人内容。

官网源脚本：`userSpace.b68a7b83544394bd4593.js`、`notification.12b48cfc3f5f38b8fc9d.js`、`credit.55c6356fb42265f63a63.js`、`board.1835d95b7fab7c7d4d3c.js`、`stardustList.3b664b2c66ef0c637662.js`、`/assets/index-WNVpTr5o.js`。

## 帖子图片

图床的网页嵌入请求需要 `Referer: https://www.nodeseek.com/`。客户端携带官网来源与图片 Accept，忽略旧的错误缓存；不向图床传递 NodeSeek Cookie 或 Authorization。使用 ImageIO 将长边缩小到最多 1600 像素，图床列表的缩略图最多 240 像素。解码缓存合计最多 12 张、24 MB，读取失败时显示重试。

## 用户主页与私聊补充

公开主页使用 `readme=1`，官网返回 `followed` 表示当前登录账号是否关注对方。`signature=1` 只用于读取自己的资料。用户主题和回复使用 `list-discussions` / `list-comments`，缓存按当前登录账号区分。

私聊会话返回 `talkTo`（对方资料）和 `msgArray`。客户端检查会话用户编号及每条消息的发送者 / 接收者，按消息编号排序。新私聊支持正整数用户编号或 HTTPS NodeSeek `/space/{uid}` 链接；先读取资料、确认对方，再打开会话，隐藏自己给自己发私信的入口。

发送接口沿用官网的 `{receiverUid,content,markdown}`。只有点击发送才提交；失败时保留草稿，不自动重发。草稿按登录账号和收件人分别保存在本机。会话可见且 App 在前台时每 10 秒读取新消息，离开会话或切到后台后停止；已读只标记发给当前账号的消息。新增私信不会强制打断正在阅读旧消息的滚动位置。

私聊目前支持文字与 Markdown。

## 其他原生功能

- 编辑：`POST /api/content/edit-discussion` 使用 `{mode:"edit-discussion",content,title,postId,rank}`；`edit-comment` 使用 `{mode:"edit-comment",content,commentId}`。新发帖保留 category，编辑主题不提交 category。四种编辑请求都带官网的 `csrf-token`。内版发帖收费 5 鸡腿；已有主题改为私有收费 10 鸡腿，先确认。
- 置顶：`POST /api/content/pin-comment`，`{commentId,action:"add"或"remove"}`。只在自己主题的回复中显示；置顶确认 5 鸡腿，取消免费。
- 关注列表：`GET /api/fans/follow`；粉丝：`GET /api/fans/fans`。响应为 `{success,memberList}`。注意接口是单数 `follow`。
- 查找用户：`GET /api/account/find/{encodedKeyword}`，响应 `memberList`。
- 今日进度：`GET /api/progress/today`；读发帖、评论奖励次数和免费鸡腿额度。
- 邀请：`GET /api/invite/list?page={page}`，每页 50；`GET /api/invite/config` 返回当前启用方式及费用。购买 `POST /api/invite/buyOne`，`{payment:"coin"或"stardust"}`，使用官网持久会话中的 `csrf_token` 和 `x-csrf-challenge:simple-token`。缺少验证信息时提示打开官网邀请页，不自动购买或重试。
- 投票：`GET /api/vote/info/{id}`；创建 `POST /api/vote/info`，`{title,multiple,isPublic,items:[text]}`；提交 `POST /api/vote/voteforitem`，`{ids:[vote_item_id]}`；结束 `POST /api/vote/lock/{id}`，`{locked:true}`；公开参与者 `GET /api/vote/voter-of-item?id={item}&page={page}`。创建响应只要求 `vote.id`。投票不可修改，结束前提示普通用户不能重新开启。
- 星尘：准备转账 `POST /api/stardust/payment-prepare`，`{receiver_id,origin}`；提交 `/api/stardust/send`，`{member_id,diff,ref_id}`。以准备接口返回的收款人名称再次确认。收款代码沿用 `nsapp://stardust-receive?...`；一次支付模式先检查对方 / Ref ID 对应的历史记录。提交失败不自动重复转账。
- **官网请求头**：官网投票和星尘脚本的 fetch client 模块为这些 API 设置 `x-dynamic-sign`。值为 SHA-1 十六进制：`[method,absoluteURL,navigator.userAgent,exactBody].join("\n\n")`。客户端在同一 WebPage 中按相同格式设置；不保存或打印登录凭据。
- 抽奖：`GET /api/content/floor-data?postId={id}&time={毫秒}`。使用官网相同 Drand chain、round 计算、cyrb128 + sfc32 排序、起始楼层与重复用户规则。
- 管理记录：只读 `GET /api/admin/ruling/page-{page}`、`id-{id}`；搜索附加 `search`，每页 20，最多 100 页。不展示管理员写入操作。
- 安全设置：头像 `POST /api/avatar/upload`，multipart 文件字段 `img`，普通字段 `token="123456798"`、`name="avatar"`，请求头 `x-csrf-challenge:simple-token`；原生预览居中裁成 100×100 PNG。上传格式参考 Nodyssey。密码 `/api/account/changePassword`，`{oldPassword,password}`；双因素 `/api/account/otp`，`{action:"create"或"remove",password}`，状态 `/otp-status`。双因素密钥仅保留在当前页面内存，不写入草稿或偏好设置。
- 官网显示设置：`POST /api/preference/list`、`/set`；`enable_festivous_style`；CSS `GET/POST /api/style`，提交 `{style}`。按 `enableCustomedStyle`、rank 或 dev 角色决定是否显示 CSS 编辑。

官网部分字段是布尔值，部分是 SQL 的 0/1。`WebsiteFlag` 兼容这两种格式，缺失保留未知，拒绝其他数字；不会把缺失状态一律当成已关闭。

主要来源：[邀请脚本](https://www.nodeseek.com/assets/index-DSpJFFoi.js)、[账号设置脚本](https://www.nodeseek.com/assets/index-WNVpTr5o.js)、[投票脚本](https://www.nodeseek.com/static/js/vote.88e0511fb187a45a164d.js)、[抽奖脚本](https://www.nodeseek.com/static/js/lucky.f7803609f35861b4ec4d.js)、[管理记录脚本](https://www.nodeseek.com/static/js/ruling.79933788162a40da9798.js)。

官网在投票之前不返回 `count` 和 `voters`，客户端此时将票数和参与者视为未知。

## 普通用户接口补充

以下接口格式参考 [Nodyssey 7eccd05](https://github.com/5151561/nodyssey/tree/7eccd05bc45093dbf2fe31671ebd32979a0c6aee)。

| 用途 | 接口与格式 | App 行为 |
| --- | --- | --- |
| 动态版块 | `GET /api/content/list-categories`，`{success,data:[{key,cn_text,adminOnly}]}` | 浏览和编辑器读取服务端名称与顺序，新发帖排除 `adminOnly`。读取失败时保留已有列表并提供重试 |
| 私信全部已读 | `POST /api/notification/message/markViewed?all=true`，无正文 | 用户确认后提交，再刷新列表及未读数 |
| Telegram | 设置页 `__config__.user.telegram_id` 判断绑定；`GET /api/account/telegram` 读取 `telegramDetail`；`POST /api/account/unbind-telegram` 无正文 | 原生展示及解绑确认，绑定沿用官网授权 |
| 原生登录 | `POST /api/account/signIn`，首次 `{username,password}` 加 `x-captcha-token`、`x-captcha-source:turnstile` | 内嵌官网 Turnstile，`need2FA=true` 时使用返回的 `otpSession` 提交 `{otp_code,otp_session}`，第二步省略验证码请求头 |
| NodeImage | 独立服务 `https://api.nodeimage.com`；上传 `POST /api/upload`，文件字段 `image`；列表 `GET /api/v1/images`；删除 `DELETE /api/v1/delete/{imageId}` | 请求使用 X-API-Key，不携带论坛 Cookie。读取 `links.direct`，也支持直接读取 `url`。密钥按论坛账号保存在本机 Keychain，删除前确认 |

账号操作和互动接口先读取服务器的 JSON 错误说明，再处理 HTTP 状态；HTML 验证页面会提示打开官网。`list-comments` 的 text 按 HTML 提取文字、换行和图片替代文字，移除脚本与样式，摘要不再按 Markdown 解释。网页请求测试使用模拟响应；`scripts/verify-account-html.swift` 在临时 WebKit 会话中检查 HTML 转文字，不访问网络。
