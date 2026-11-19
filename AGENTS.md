# iNod 项目开发说明

iNod 是非官方 NodeSeek 客户端，使用 SwiftUI，支持 iOS 26、iPadOS 26 和 macOS 26 及更新版本。Mac 版通过 Mac Catalyst 运行。用 Xcode 打开 `NodeSeek.xcodeproj`，选择 `NodeSeek` scheme。

## 代码放在哪

- `NodeSeek/App` 管 App 启动、导航和官网页面。功能界面放在 `NodeSeek/Features` 对应目录，通用组件放在 `NodeSeek/Shared`，布局和样式放在 `NodeSeek/DesignSystem`。
- `Sources/NodeSeekClient` 管官网请求、WebKit 会话、缓存、草稿和媒体。`Sources/NodeSeekCore` 放数据类型、解析和可独立测试的规则。App 可以使用两个模块，Client 可以使用 Core。
- `NodeSeek/` 和 `NodeSeekUITests/` 由 Xcode 自动同步。新增 Swift 文件时放进对应目录即可。

## 改功能时

- 改官网请求或解析时，先看已有的 `SiteReader`、`SiteScripts` 和 `SiteDataStore`。沿用现有 WebKit 会话，确认改动后账号切换仍会清理旧账号的缓存。官网请求格式见 [docs/API.md](docs/API.md)。
- 改界面时，复用 `DesignSystem`。列表、卡片和浮动栏用 `SeekLayout` 保持列宽和对齐。先在 iPhone 检查，涉及宽屏排版时再检查 iPad 或 Mac 窗口。 [界面设计检查](docs/DESIGN.md)

## 怎么检查

在仓库根目录按改动选择命令。

| 改动 | 命令 |
| --- | --- |
| Core 或 Client | `xcrun swift test` |
| 官网请求脚本或 HTML 解析 | `sh scripts/verify-website.sh` |
| SwiftUI 界面 | `node scripts/check-design.mjs` |

- 单元测试放在 `Tests/NodeSeekCoreTests` 或 `Tests/NodeSeekClientTests`。界面测试放在 `NodeSeekUITests`，优先用 `ForumFixture` 的离线数据和虚构账号。
- 界面测试用 `NodeSeek` scheme 在 Xcode 按 `⌘U`，也可以按维护指南运行命令。两个脚本检查都需要 Node.js。 [CI 维护指南](docs/CI.md)

## 提交 PR

- PR 只要改了 Swift 代码，就必须在 PR 描述的「截图或录屏」一节上传对应的改前和改后图片。图片作为 GitHub 附件上传，不提交到仓库。 [贡献指南](CONTRIBUTING.md)
