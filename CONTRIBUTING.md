# 参与 iNod 开发

## 报告问题或建议功能

先搜索已有 Issue。报告问题时，请写清 App 和 iOS 版本、设备、复现步骤和预期结果。建议功能时，请描述你想完成什么、现在卡在哪里。分享截图、录屏或日志前，遮住账号、私信、Cookie、验证码和密钥。

## 在本机运行

需要装有 Xcode 和 iOS 模拟器的 Mac。建议使用与 CI 相同的 Xcode 27.2。打开 `NodeSeek.xcodeproj`，选择 `NodeSeek` 和一个 iOS 26 或更新版本的 iPhone、iPad 模拟器，或 **My Mac (Mac Catalyst)**，按 `⌘R` 运行。模拟器不需要 Apple 开发者账号。真机运行时，在 **Signing & Capabilities** 中选择自己的开发者团队。

```sh
xcrun swift test
sh scripts/verify-website.sh
```

第二条命令需要 Node.js。要跑界面测试，在同一个模拟器按 `⌘U`。可在 [CI 维护指南](docs/CI.md) 找到命令行跑法和测试文件位置。

## 提交 Pull Request

1. Fork 仓库，从 `main` 开一个分支。一个 PR 专注于一个问题或功能。计划大幅调整界面或请求方式时，可以先开 Issue 讨论。
2. 修复问题时，尽量补上能重现原问题的测试。测试数据用虚构的内容，别提交真实账号数据或签名文件。
3. 改了界面时：
   - 按[界面设计检查](docs/DESIGN.md)逐条自查，并在 iPhone 模拟器上点一遍；改了列表、卡片或浮动栏时，再看一眼 iPad 或 Mac 窗口。
   - 在 PR 的“截图或录屏”一节**上传**改动前后的截图或录屏，直接拖进 PR 描述即可。只写“本地已确认”“未上传”不算。
   - 用命令行时，`gh pr create` 和 `gh pr edit` 的 `--attach` 会把文件传成 GitHub 附件（需要 gh 2.101 或更新）：描述里写 `![改后](./after.png)`，再加 `--attach ./after.png`，引用会自动换成上传后的地址。表格里的 `<img src>` 不会被替换，要先上传，再把地址填进去。
   - 截图只放 GitHub 附件，不要提交进仓库，也不要另开分支存放：图片会永远留在 git 历史里，分支一删旧 PR 的图就失效。
   - 上传前遮住账号、私信等个人信息，尽量用未登录状态或测试数据截图。
   - **Screenshots for interface changes** 检查会核对：改了 `NodeSeek/` 下的 Swift 代码（注释除外）而 PR 描述里没有图片或视频时，检查不通过。
4. 向公开仓库的 `main` 提交 PR，说明改了什么、怎么检查的。关联已有 Issue，并在 PR 的 **Checks** 查看自动检查结果。
