# iNod 的代码怎么分工

| 要改的内容 | 从哪里看 | 这里负责什么 |
| --- | --- | --- |
| 启动、登录状态和跳转 | [NodeSeekApp](../NodeSeek/App/NodeSeekApp.swift)、[AccountSession](../Sources/NodeSeekClient/Session/AccountSession.swift)、[ForumNavigationStack](../NodeSeek/App/Navigation/ForumNavigationStack.swift) | App 创建账号会话，传给各页面。账号变化时，会话重置通知、收藏等数据，导航清掉旧账号打开的页面。 |
| 页面和交互 | [Features](../NodeSeek/Features)、[Shared](../NodeSeek/Shared)、[DesignSystem](../NodeSeek/DesignSystem) | 功能页面决定展示什么。普通列表用 ResourceLoader 管理读取、分页和重试。跨页面共用的组件、布局和样式分别放在 Shared 和 DesignSystem。 |
| 官网读写和本机保存 | [NodeSeekClient](../Sources/NodeSeekClient) | SiteDataStore 检查账号、复用相同请求并管理缓存。SiteReader 在共用的 WebKit 网页环境里请求官网。InboxService 和 CollectionsService 负责让不同页面看到一致的未读数和收藏状态。 |
| 数据和规则 | [NodeSeekCore](../Sources/NodeSeekCore) | 帖子、楼层、草稿、链接等类型和处理规则放在这里。Core 可以独立测试，Client 可以使用 Core，App 可以使用两者。 |

例如，打开帖子时，列表把帖子交给导航，ThreadView 用帖子编号、页码和屏蔽设置向 SiteDataStore 读取。页面可以先显示本机保存的内容。官网返回后，ThreadView 检查账号和当前请求，再更新楼层。快速回复和完整编辑器都通过 WebsiteAction.publish 提交，同一条回复的请求格式只定义一次。具体字段见[官网接口说明](API.md)。

## 修改这些功能时要检查什么

- **离线读帖。** 回复、编辑或置顶后，移除当前账号保存的该帖各页和旧列表。新发帖只影响列表和相关账号数据，原有帖子的正文仍可离线阅读。收藏或送鸡腿时，帖子列表仍可使用。内存和本机文件按同一规则处理，写操作返回前会等相关文件处理完毕。[缓存实现](../Sources/NodeSeekClient/Website/SiteDataStore.swift)、[离线重开测试](../Tests/NodeSeekClientTests/ThreadCacheTests.swift)
- **从通知打开中间楼层。** Core 的 ThreadPages 保存已读到的连续页码，检查返回的帖子和页码，合并相邻页并去掉重复评论。它把新增的评论交回 ThreadView，页面据此更新图片和滚动位置。[分页规则](../Sources/NodeSeekCore/Posts/ThreadPages.swift)、[分页测试](../Tests/NodeSeekCoreTests/PinnedCommentsTests.swift)
- **重试网络检测。** Client 的报告记录每个请求的原始测量，Core 的报告用于展示和决定还能重试哪些项。转换时保留已测出的速度和延迟。网站可访问性按站点合并结果。取消重试或切换网络时，保留上次已完成的站点和线路。如果重试时出口 IP 已改变，名单检测会按新地址重新查询。新增检测项时，在离线测试里走过首次成功、部分失败和再次尝试三种情况。[报告转换](../Sources/NodeSeekClient/Quality/LiveNetworkQualityTester.swift)、[检测测试](../Tests/NodeSeekClientTests/QualityIntegrationTests.swift)
