# iNod 手绘图标

在 [InkIcons](InkIcons) 里按使用场景找原稿。每个 SVG 的文件名对应代码里的资源名，图中的 `<title>` 写中文用途。例如，帖子列表的阅读量用 `Image(.inkReadCount)`。[阅读量原稿](InkIcons/帖子与回复/InkReadCount.svg)

## 看图

在仓库根目录运行下面的命令，然后用浏览器打开输出的 HTML 文件。页面可以搜索中文用途、场景和资源名，点击图标可查看原稿。顶部示例按界面常用字号排列，下面的目录可以切换三个尺寸。浏览器预览用于比较，最终显示以设备为准。

```sh
uv run scripts/icons/manage.py preview
```

## 改图

1. 在对应场景目录编辑或添加 `Ink用途.svg`。用途相同的地方共用一个资源，含义不同的操作分别命名，例如帖子和回复各有一个“更多”。
2. 使用 `viewBox="0 0 32 32"` 的 SVG，包含一个 `<title>` 和一条填充的复合路径 `<path d="…"/>`。从绘图软件导出时，将描边转为轮廓并应用变换，参考同组图标确定大小和位置。
3. 默认从同一份原稿生成小、中、大三种尺寸。某个尺寸需要单独调整时，在同目录添加 `Ink用途-S.svg` 或 `Ink用途-L.svg`，沿用相同画板。常规尺寸始终读取主原稿。
4. 运行以下命令，并将原稿和生成的 Xcode 资源一起提交。移动或删除原稿时，同时移除旧位置对应的 `.symbolset` 目录，检查会列出具体路径。

```sh
uv run scripts/icons/manage.py generate
uv run scripts/icons/manage.py check
```

Xcode 直接使用 [生成的资源](../NodeSeek/Assets.xcassets/InkIcons)。预览存放在本地的 `build/icon-preview/index.html`。只有生成、预览和检查图标时需要 uv，它会准备脚本所需的 Python 和字体工具。
