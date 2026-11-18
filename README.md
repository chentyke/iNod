# iNod

非官方 NodeSeek 客户端，支持 iPhone、iPad 和 Mac

使用 SwiftUI，最低支持 iOS 26 / iPadOS 26，Mac 版通过 Mac Catalyst 运行（macOS 26 或更新）。直接读取官网页面和官网使用的 JSON 接口，无第三方依赖。

## 打开项目

用 Xcode 26.2 或更新版本打开 `NodeSeek.xcodeproj`，选择 `NodeSeek` scheme 和 iPhone、iPad 模拟器或 **My Mac (Mac Catalyst)** 后运行。真机运行需要在 Signing & Capabilities 中选择自己的开发者团队。

```sh
xcrun swift test
sh scripts/verify-website.sh
```

第二条命令需要 Node.js。想报告问题、提建议或提交代码，可以看[贡献指南](CONTRIBUTING.md)。界面测试和 GitHub Actions 的运行方式见 [CI 维护指南](docs/CI.md)。

## 已完成

- 原生帖子列表，版块选择、新评论 / 新帖子排序、分页；底部独立搜索入口。
- 原生正文和评论阅读、引用、列表、表格、代码块、混排图片和点按放大；AC娘、洋葱头、小黄鸡、Fluent 表情及动图。
- 登录后可用帖子书签或列表左滑收藏，收藏跟随 NodeSeek 账号；阅读页使用三个独立、带颜色的 Liquid Glass 悬浮按钮。
- 原生登录与双因素验证码输入，内嵌官网人机验证；共用系统 WebKit 的持久会话，登录完成、返回 App 和打开「我的」时自动更新账号。
- 「我的」中提供原生通知（回复 / @我 / 私信）、主题、回复、鸡腿和星尘明细、签到榜、个人主页与账号设置。
- 原生私聊列表与会话；从主页发起新私聊，或输入用户编号 / 官网主页链接查找收件人。支持本机草稿、Markdown 预览、搜索已有私信，以及前台会话的新消息刷新。
- 公开个人主页、主题 / 回复列表、关注与取消关注、分享主页；帖子作者和评论作者可直接进入主页。编辑资料只对自己显示。
- 通知已读、固定或随机签到、个人介绍与签名编辑、首页版块选择、屏蔽用户、登录记录与退出登录。
- 帖子图片携带官网来源信息，修复图床将原生请求识别为直链下载而返回 403 的问题；缩小解码尺寸并限制内存缓存。
- 帖子及评论可原生点赞、投喂鸡腿与反对；先查询免费次数并确认费用，成功后使用官网返回的数量更新按钮与余额。
- 原生发帖、编辑主题和回复、引用回复、表情选择、投票创建与参与、星尘收款组件；按账号和帖子保存本机草稿，支持 Markdown 预览。
- 楼主置顶回复、页码跳转、全局显示被屏蔽内容；版块列表从官网更新，包括内版等当前开放的版块。
- 用户搜索、关注 / 粉丝列表、等级和每日进度、邀请管理与购买、抽奖工具、推荐阅读、管理记录及合作商家目录。
- 原生头像选择、修改密码、双因素验证设置、星尘转账与记录筛选；邮箱、手机号和 Telegram 授权仍使用官网验证流程。
- Telegram 绑定状态与解绑、私信全部已读；NodeImage 图片上传、选择已有图片和删除图片，图床密钥按账号保存在本机 Keychain。
- 支持深色模式、系统字体大小与 VoiceOver。
- iPad 社区首页左侧显示帖子列表，右侧阅读正文和回复，窗口变窄时切换为单栏。iPad 的侧边栏可以收起。Mac 和其他宽屏页面的内容居中，最宽 760 点。实体键盘可用 ⌘N 发帖、⌘R 回复。

官网的列表是 HTML，详情数据来自页面 `temp-script` 中的 Base64 JSON。启动时使用系统 WebKit 建立官网会话，之后在同一个网页环境里请求页面或 JSON 接口；解析页面时不执行其中的脚本，也不加载广告和图片。原生图片单独按需读取。短期缓存和相同请求合并减少重复等待，有缓存的页面先显示内容再更新，下拉刷新会重新请求；账号变化和退出登录会清空缓存，回复、标为已读、送鸡腿等常见操作只清理相关数据。接口记录见 [docs/API.md](docs/API.md)，速度检查见 [docs/PERFORMANCE.md](docs/PERFORMANCE.md)。

## 项目结构

App 通过本地 Swift Package 链接 `NodeSeekClient` 和 `NodeSeekCore`。依赖方向为 `App → NodeSeekClient → NodeSeekCore`，App 也可以直接使用 Core 的类型。

- `NodeSeek/App` 组装账号、标签页、跨功能跳转与官网页面。
- `NodeSeek/Features` 按帖子、收藏、收件箱、成员、账号、社区工具和图床组织页面。页面负责筛选、分页、滚动和弹窗。
- `NodeSeek/Shared` 提供 Markdown、表情选择、头像、图片预览和加载界面。`NodeSeek/DesignSystem` 提供颜色、按钮和列表样式。
- `Sources/NodeSeekClient` 管理 WebKit、官网请求、缓存、草稿和媒体。登录、收件箱和收藏分别由 `Session`、`Inbox` 和 `Collections` 管理。已读成功后先更新已加载的会话与列表，总未读数仍取自官网。
- `Sources/NodeSeekCore` 保存数据类型、链接、Markdown 解析和可独立测试的规则。
- `Tests` 分别检查 Core 的规则和 Client 的请求格式、状态更新及账号切换。

## 使用限制

验证码、登录 / 注册、邮箱 / 手机 / Telegram 授权使用系统 WebKit 的官网流程。复杂 HTML、外站交互嵌入和特殊网页排版可通过帖子菜单的官网入口查看。功能对照见 [docs/FEATURES.md](docs/FEATURES.md)。

草稿保存在设备上。仓库不包含登录凭据、Cookie 或开发者签名文件。官网页面结构或内部接口变化后，可能需要更新 `SiteScripts` 和数据类型。

## 开源许可证

本项目使用 [MIT 许可证](LICENSE)。
