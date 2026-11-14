# CI 维护指南

## GitHub Actions

[CI 工作流程](../.github/workflows/ci.yml)会在有人向 `main` 提交或更新 PR、向 `main` 推送时运行，也可以在 **Actions → CI → Run workflow** 手动启动。

| 检查名称 | 运行内容 |
| --- | --- |
| Swift and website checks | 运行 Swift 单元测试，再检查网页请求格式和 WebKit 解析。 |
| iOS UI tests | 构建 App，在 iPhone 17 模拟器上跑界面测试。失败时，可在运行页面的 **Artifacts** 下载测试报告，用 Xcode 打开 `.xcresult`。 |

公开仓库的检查使用 GitHub 提供的 `xcode-27` 环境，选用 Xcode 27.2 和 iOS 27.2 模拟器。测试使用本地样本和模拟响应，无需 Apple 签名、NodeSeek 账号或 GitHub Secrets。[GitHub 提供的 Xcode 和模拟器版本](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

新仓库首次跑通 CI 后，可在 `main` 的分支规则里把这两项设为合并前必须通过的检查。来自 Fork 的首次 PR 可能需要维护者在 PR 页面点 **Approve workflows to run**。[GitHub 对外部贡献者工作流程的说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/approve-runs-from-forks)

## 在本机运行

在仓库根目录执行。网页检查需要 Node.js。

```sh
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
- App 启动、版块选择和页面跳转等需要实际点界面的检查放在 [NodeSeekUITests](../NodeSeekUITests/)。现有用例启动 App 时传入 `--ui-test-offline`，模拟官网连不上，避免依赖官网或模拟器里已有的登录状态。这个参数只在 Debug 构建中生效。
- 网页请求脚本和 HTML 解析的检查由 [verify-website.sh](../scripts/verify-website.sh) 运行。

如果改动涉及真实登录、验证码或向官网提交数据，请在 PR 写明手动检查的步骤和结果。
