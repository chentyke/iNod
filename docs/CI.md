# CI 维护指南

## GitHub Actions

[CI 工作流程](../.github/workflows/ci.yml)会在 PR 新建、推送提交或重新打开时运行，不限目标分支。也可以在 **Actions → CI → Run workflow** 手动跑完整检查。

PR 上的 CI 会测试 GitHub 试合并后的代码，合并时不会另外启动一轮。只改 PR 标题或描述时，也只会重跑[描述检查](../.github/workflows/pr-description.yml)。把一组有依赖的 PR 改为合入 `main` 后，如果 GitHub 提示分支落后，点 **Update branch** 就会重新检查；分支没有落后时，可以在 PR 的 **Checks** 页面点 **Re-run all jobs**。

如果 PR 只改了项目说明、许可证、GitHub 的 Issue 或 PR 模板、`docs/` 下的 Markdown 或 `docs/readme/` 下的 PNG，CI 只运行设计、图标和 PR 描述检查。如果还改了 Swift 包的单元测试或测试数据，CI 会加跑 Swift 和网页检查。涉及 App、界面测试、构建配置或 CI 脚本的改动，以及手动启动的 CI，都会运行完整检查。

| 检查名称 | 运行内容 |
| --- | --- |
| Design checks | 按[界面设计检查](DESIGN.md)扫描 SwiftUI 代码里的渐变、大面积状态色和醒目的彩色描边。 |
| Screenshots for interface changes | PR 改了界面代码时，检查描述里有没有上传截图或录屏。改完 PR 描述会自动重新检查。 |
| Swift and website checks | 运行 Swift 单元测试（含离线头像缓存），再检查网页请求格式和 WebKit 解析。 |
| iOS UI tests | 两台 GitHub Mac 各用一个 iPhone 17 模拟器，分组跑完所有适用的界面测试。每组只把失败的测试再跑一次，两次都失败就阻止合并。失败时，可在运行页面的 **Artifacts** 下载对应组的 `.xcresult` 测试报告，用 Xcode 打开。 |
| iPad UI tests | 在 iPad Pro 13 英寸 (M5) 模拟器检查首页双栏、侧边栏的深浅色对比、横屏排版、键盘快捷键、帖子分页，以及签到、等级进度和星尘明细的列宽。GitHub 的 iPad 模拟器很慢，偶尔在两个测试之间关不掉 App，所以失败的测试会重跑一次，两次都失败才算不通过。失败时同样可下载测试报告。 |
| Mac UI tests | 构建 Mac Catalyst 版 App，检查启动后侧边栏列出全部标签页、深色模式下选中的标签页看得清，首页和帖子页卡片在侧边栏旁居中成一栏。帖子页由 App 在测试时自己打开（`NODESEEK_UI_TEST_OPEN_POST`，只在 Debug 构建生效），不用点击。GitHub 的 Mac 环境里，界面测试发出的点击和按键到不了 App 的内容，所以需要操作的测试只在 iPhone 和 iPad 上跑；Mac 上的点击、切换标签页和快捷键要手动检查。本机跑 Mac 界面测试时，指针悬停能送到 App，点击同样送不到。 |

iPhone 或 iPad 已经启动，但 Xcode 找不到设备，或 XCTest 在第一个测试开始前崩溃时，CI 会在同一设备上再试一次。两次启动都失败时，运行页面会保留 Xcode 生成的两份测试报告。

公开仓库的检查使用 GitHub 提供的 `xcode-27` 环境，选用 Xcode 27.2 和 iOS 27.2 模拟器。测试使用本地样本和模拟响应，无需 Apple 签名、NodeSeek 账号或 GitHub Secrets。[GitHub 提供的 Xcode 和模拟器版本](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

`main` 的改动必须通过 PR 合并，合并前必须通过 Swift and website checks 和 iOS UI tests。来自 Fork 的首次 PR 可能需要维护者在 PR 页面点 **Approve workflows to run**。[GitHub 对外部贡献者工作流程的说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/approve-runs-from-forks)

## 打包 Release

在 Xcode 选择 `NodeSeek` App target，在 **General → Identity → Version** 更新版本。合并版本改动前，确认 PR 的 CI 通过。

在 **Actions → Package Release → Run workflow** 选择 `main`。[打包流程](../.github/workflows/release.yml)读取 App 版本，生成 iPhone 和 iPad 用的未签名 IPA、Mac 用的 DMG，各带一个 SHA-256 校验文件，并创建对应的 Release 草稿。检查附件和发布说明后，在 **Releases** 点 **Publish release**。

IPA 安装前需要自行签名。Mac 版只有临时签名（ad-hoc），没有经过 Apple 公证，第一次打开时要在 **系统设置 → 隐私与安全性** 点 **仍要打开**；发布说明里已写明这一步。

只想打包时，取消勾选 **Create a GitHub Release draft**，在这次运行的 **Artifacts** 下载文件。即使这个版本已有标签，也可以用这种方式重新打包。

### Mac 自动更新

Mac 版每天检查一次 GitHub 上最新的正式版本，有新版本时会自动下载。也可以从 Mac 顶部的 **NodeSeek → 检查更新…** 手动检查。更新包通过签名检查后，点 **重启并安装** 才会替换旧版。第一次需要从 DMG 手动安装带有更新功能的版本。

首次启用 App 内安装时，生成一份专用的 Ed25519 签名私钥。安全备份后，把它存为仓库的 Actions Secret `MAC_UPDATE_PRIVATE_KEY`。以下命令会直接把生成的私钥写入只有当前用户能读的文件。

```sh
key_file=$(mktemp "$HOME/iNod-update-key.XXXXXX")
xcrun swift scripts/sign-mac-update.swift generate-key > "$key_file"
gh secret set MAC_UPDATE_PRIVATE_KEY < "$key_file"
```

把生成的文件存到安全的地方，后续发布继续使用同一份密钥。打包流程会把对应的公钥放进 Mac App，并将更新用的 ZIP 和 `.ed25519` 签名一起加进 Release。没有配置这个 Secret 时，Mac 版发现新版本后可前往 GitHub 下载页。

## 在本机运行

在仓库根目录执行。网页检查需要 Node.js。

```sh
node scripts/check-design.mjs
xcrun swift test
sh scripts/verify-website.sh
xcodebuild -project NodeSeek.xcodeproj -scheme NodeSeek \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- test
xcodebuild -project NodeSeek.xcodeproj -scheme NodeSeek \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=27.2' \
  -only-testing:NodeSeekUITests/AdaptiveLayoutTests \
  -only-testing:NodeSeekUITests/ThreadHistoryTests \
  -only-testing:NodeSeekUITests/AttendanceViewTests/testUncheckedAttendanceShowsActionsAndKeepsReadableColumn \
  -only-testing:NodeSeekUITests/ProgressViewTests/testUpgradingProgressShowsLevelQuotasAndKeepsReadableColumn \
  -only-testing:NodeSeekUITests/StardustHistoryViewTests/testStardustHistoryDisplaysBalanceRecordsAndNavigates \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- test
xcodebuild -project NodeSeek.xcodeproj -scheme NodeSeek \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -only-testing:NodeSeekUITests/AdaptiveLayoutTests/testAllTabsAreOnScreen \
  -only-testing:NodeSeekUITests/AdaptiveLayoutTests/testFeedKeepsAReadableCentredColumn \
  -only-testing:NodeSeekUITests/AdaptiveLayoutTests/testThreadCardsAndReplyBarShareOneColumn \
  -only-testing:NodeSeekUITests/AdaptiveLayoutTests/testConversationBubblesAndComposerShareOneColumn \
  -only-testing:NodeSeekUITests/AdaptiveLayoutTests/testMacNotificationsAndPrivateChatsHaveSeparatePages \
  -only-testing:NodeSeekUITests/AdaptiveLayoutTests/testSidebarSelectionIsReadableInDarkMode \
  -only-testing:NodeSeekUITests/AdaptiveLayoutTests/testMenuBarIncludesManualRefreshCommand \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- ENABLE_HARDENED_RUNTIME=NO test
```

本机用临时签名跑 Mac 界面测试时加上 `ENABLE_HARDENED_RUNTIME=NO`，否则测试包会因签名不一致载入失败。Mac 的界面测试会接管鼠标和键盘，跑的时候别动电脑。检查本机指针悬停时，用 `-only-testing:NodeSeekUITests/DesignChecklistTests/testPointerHoverOpensTheDock` 替换上面 Mac 命令里的四个测试选项。本机模拟器不同的话，把 `name` 和 `OS` 改成已安装的型号和版本。也可以在 Xcode 里选择模拟器，按 `⌘U` 跑界面测试。只想跑账号状态的 Swift 单元测试时，可以执行 `xcrun swift test --filter AccountSessionTests`。

## 测试写在哪里

- 数据解码、链接、Markdown 和草稿规则放在 [Tests/NodeSeekCoreTests](../Tests/NodeSeekCoreTests/)。
- 登录状态、收藏、私信和请求格式放在 [Tests/NodeSeekClientTests](../Tests/NodeSeekClientTests/)。
- App 启动、相册入口和页面跳转等界面检查放在 [NodeSeekUITests](../NodeSeekUITests/)。iPad 和 Mac 的宽屏排版与键盘快捷键放在 `AdaptiveLayoutTests`，离线的首页和帖子样本放在 `ForumFixture`。[界面设计检查](DESIGN.md)里能在运行中量出来的间距和收起行为放在 `DesignChecklistTests`。测试在 Debug 构建中注入离线状态或模拟账号和响应，避免依赖官网或模拟器里已有的登录状态。
- 网页请求脚本和 HTML 解析的检查由 [verify-website.sh](../scripts/verify-website.sh) 运行。

如果改动涉及真实登录、验证码或向官网提交数据，请在 PR 写明手动检查的步骤和结果。
