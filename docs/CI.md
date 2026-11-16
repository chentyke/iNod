# CI 维护指南

## GitHub Actions

[CI 工作流程](../.github/workflows/ci.yml)会在以 `main` 或 `image-stack/` 系列分支为目标的 PR 新建或推送提交时运行，也可以在 **Actions → CI → Run workflow** 手动启动。

合并到 `main` 后不会再跑一遍：`main` 要求 PR 先更新到最新再合并，PR 上的检查已经覆盖合并后的代码。只改 PR 标题或描述时，也只会重跑[描述检查](../.github/workflows/pr-description.yml)。把一组有依赖的 PR 改为合入 `main` 后，如果 GitHub 提示分支落后，点 **Update branch** 就会重新检查；分支没有落后时，可以在 PR 的 **Checks** 页面点 **Re-run all jobs**。

| 检查名称 | 运行内容 |
| --- | --- |
| Design checks | 按[界面设计检查](DESIGN.md)扫描 SwiftUI 代码里的渐变、大面积状态色和醒目的彩色描边。 |
| Screenshots for interface changes | PR 改了界面代码时，检查描述里有没有上传截图或录屏。改完 PR 描述会自动重新检查。 |
| Swift and website checks | 运行 Swift 单元测试，再检查网页请求格式和 WebKit 解析。 |
| iOS UI tests | 一开始就在后台启动 iPhone 17 模拟器，同时构建 App 和测试；等模拟器启动完成后跑界面测试。模拟器刚启动的几分钟会占满 CPU，和构建重叠能少等一段。失败时，可在运行页面的 **Artifacts** 下载测试报告，用 Xcode 打开 `.xcresult`。 |

公开仓库的检查使用 GitHub 提供的 `xcode-27` 环境，选用 Xcode 27.2 和 iOS 27.2 模拟器。测试使用本地样本和模拟响应，无需 Apple 签名、NodeSeek 账号或 GitHub Secrets。[GitHub 提供的 Xcode 和模拟器版本](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

`main` 的改动必须通过 PR 合并，合并前需要通过上面的检查。如果 `main` 有新提交，请先更新 PR 分支，再等 CI 跑完。来自 Fork 的首次 PR 可能需要维护者在 PR 页面点 **Approve workflows to run**。[GitHub 对外部贡献者工作流程的说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/approve-runs-from-forks)

## 打包 Release

在 Xcode 选择 `NodeSeek` App target，在 **General → Identity → Version** 更新版本。合并版本改动前，确认 PR 的 CI 通过。

在 **Actions → Package iOS Release → Run workflow** 选择 `main`。[打包流程](../.github/workflows/release.yml)读取 App 版本，生成未签名的 IPA 和 SHA-256 校验文件，并创建对应的 Release 草稿。检查附件和发布说明后，在 **Releases** 点 **Publish release**。IPA 安装前需要自行签名。

只想打包时，取消勾选 **Create a GitHub Release draft**，在这次运行的 **Artifacts** 下载文件。即使这个版本已有标签，也可以用这种方式重新打包。

## 在本机运行

在仓库根目录执行。网页检查需要 Node.js。

```sh
node scripts/check-design.mjs
xcrun swift test
sh scripts/verify-website.sh
xcodebuild -project NodeSeek.xcodeproj -scheme NodeSeek \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- test
```

本机模拟器不同的话，把 `name` 和 `OS` 改成已安装的型号和版本。也可以在 Xcode 里选择模拟器，按 `⌘U` 跑界面测试。只想跑账号状态的 Swift 单元测试时，可以执行 `xcrun swift test --filter AccountSessionTests`。

## 测试写在哪里

- 数据解码、链接、Markdown 和草稿规则放在 [Tests/NodeSeekCoreTests](../Tests/NodeSeekCoreTests/)。
- 登录状态、收藏、私信和请求格式放在 [Tests/NodeSeekClientTests](../Tests/NodeSeekClientTests/)。
- App 启动、相册入口和页面跳转等界面检查放在 [NodeSeekUITests](../NodeSeekUITests/)。[界面设计检查](DESIGN.md)里能在运行中量出来的间距和收起行为放在 `DesignChecklistTests`。测试在 Debug 构建中注入离线状态或模拟账号和响应，避免依赖官网或模拟器里已有的登录状态。
- 网页请求脚本和 HTML 解析的检查由 [verify-website.sh](../scripts/verify-website.sh) 运行。

如果改动涉及真实登录、验证码或向官网提交数据，请在 PR 写明手动检查的步骤和结果。
