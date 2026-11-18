# Project Quality 检测接口

`NodeSeekClient` 提供检测服务和 Swift 报告类型。界面预览可以直接用 `NetworkQualityExamples.running`、`.completed`、`.partial`、`.cancelled` 和 `.unavailable`。示例 IP 是文档专用地址。

## App 接入

网络检测页面使用 `LiveNetworkQualityTester`，本机性能页面使用 `LiveDeviceBenchmark`。两者都用 `NodeSeekCore` 中的报告类型，每次进度变化发送一份报告，页面取消时结束请求。界面测试通过 `--ui-test-offline` 播放示例，示例跑分单独保存。

重试沿用上一份报告，测速只补测缺少的统计项，线路、IP 名单和网站只重试失败的来源。开始重试时如果网络类型不同，报告保留已测得的成绩，并提示重新检测。进阶 NAT 只显示实际查到的地址和端口分配方式。邮件检查只建立 TCP 连接，不投递邮件。

本机性能方法为 `iNod Bench 1`。单核和多核各计算 128 次 1 MiB 的 SHA-256，多核版本按当前可用的处理器数量分配工作。存储使用同一份 64 MiB 文件，先顺序读写，然后各做 4096 次 4 KiB 的随机写入和读取，随机操作的位置顺序固定。存储报告使用 MB/s，随机测试同时记录每秒操作数。下方三轮真机记录属于接入前的单核和顺序读写方法。

## 首版接入

- 点击开始时，在一个 `Task` 中调用 `await NetworkQualityService().run(onProgress:)`。回调给出当前报告，最终报告由 `run` 返回。用 `currentStep` 和 `completedStepCount` 显示进度，`Step.allCases.count` 是总步数。
- 取消时调用该任务的 `cancel()`，等 `run` 返回即可显示已完成的测试。重试时再调用一次 `run`，每次都有新的 `id`。更新 SwiftUI 状态时回到 `MainActor`。
- 单项用 `QualityCheck` 显示等待、进行中、成功、无法测量和已取消。`.completed` 表示测完，单项仍可能失败。`.interrupted(.offline)` 和 `.interrupted(.networkChanged)` 表示途中停止。没开始的项保持 `.pending`。
- 测速请求发送和接收的数据合计最多约 42 MB，另有小量请求和协议开销。请求根据系统和 VPN 当前的路由发出。`network` 是系统监视到的起始网络，报告里的出口 IP 对应各自的检测请求。分流时，测速和查 IP 可能走不同的出口。
- 分享时如需隐藏 IP，使用报告里非地址字段生成分享内容。报告的原始 JSON 包含完整地址。

| 字段 | 单位与算法 | 节点和字段说明 |
| --- | --- | --- |
| `ipv4`、`ipv6` | 分别请求仅支持对应地址类型的 ipify 端点，检查实际返回地址的类型 | `source` 带请求地址和时间。地址由对应站点观察到。仅 IPv6 网络也可能经 NAT64 访问 IPv4 端点。 |
| `attribution` | 用实际查出的 IP 查询 IPinfo，记录国家、地区、城市、ASN 和该网络名称 | `attributionSource` 带数据来源和查询时间。查不到归属时仍显示出口地址。IPinfo 的匿名查询会按出口地址限制请求量。 |
| `latency` | ms。Cloudflare 请求 `bytes=0` 预热一次，取五次 HTTP 首字节时延的中位数，从请求开始计时。有有效服务端耗时时扣除它。 | 每个样本记测试时间、Cloudflare 节点代码、实际连接的地址类型（若系统提供）和失败原因。端点为 `speed.cloudflare.com/__down?bytes=0`。 |
| `jitterMilliseconds` | ms。相邻、成功且到同一节点、使用同一地址类型的时延差取绝对值，再求平均。没有这样的样本对时留空。 | 与 `latency` 共用样本。 |
| `download`、`upload` | Mbps。两方向各尝试 1 MB、10 MB、10 MB。用内容字节数除以耗时，取至少 250 ms 的样本的第 90 百分位。全是短样本时，取最大成功测试量对应的样本，标为估计值。 | 下载从请求开始计到接收结束，扣除服务端耗时。上传从请求开始计到收到响应首字节。每次记录字节数、耗时、节点和时间。 |

Cloudflare 的 HTTP 时延和抖动算法可在同节点上复测。iNod 使用较少的样本和流量，带宽统计以内容字节数为准。NodeQuality 的 NetQuality 报告采用 Speedtest.net 节点和三网 TCP 延迟，公网 IP 类型、ASN 和国家可比。测速成绩需要在同一节点用相同大小、样本数和算法复测再比较。

[NodeQuality](https://github.com/LloydAsp/NodeQuality) / [NetQuality](https://github.com/xykt/NetQuality) / [IPQuality](https://github.com/xykt/IPQuality) / [Cloudflare Speedtest](https://github.com/cloudflare/speedtest) / [ipify](https://www.ipify.org/) / [IPinfo](https://support.ipinfo.io/hc/en-us/articles/34121895556242-Legacy-Free-API-vs-IPinfo-Lite)

## 运营商节点测速

`QualityCarrierSpeedService.run(at:)` 接收一个可调用的 LibreSpeed 或 SpeedTest.cn 节点，附带运营商和城市。延迟、下载和上传均发往同一 HTTPS 来源。服务复用基础测速的时间统计和网络变化处理，分别保留三项结果。基础 Cloudflare 测速继续使用原有节点。

延迟请求先预热一次，再测五次。LibreSpeed 模式下，每个方向发送或接收 1、4、4 MiB 的测试数据，每节点合计 18 MiB，另有小量协议开销。下载必须收到约定的字节数，响应超过允许大小时结束请求。请求失败和节点限流按原样记录。

公开节点 `QualityCarrierSpeedNode.taiyuanUnicom` 对应太原联通。该节点的下载最小为 10 MiB，服务发一次 10 MiB 下载和两次 4 MiB 上传，测试数据总量仍为 18 MiB。只有握手返回测速标记、下载收到约定字节数、上传收到相符的字节数确认，才记录对应结果。电信、移动的默认节点仍待确认。

App 在网络检测的“速度”一节提供“按运营商测速”入口，页面通过 `CarrierSpeedTesting` 取得节点列表和测速报告，`LiveCarrierSpeedTester` 把服务结果换成 `SpeedMeasurement`。同一时间只测一个节点，离开页面即取消。界面测试用 `SampleCarrierSpeedTester`。

[SpeedTest.cn 公开候选清单](https://github.com/spiritLHLS/speedtest.cn-CN-ID) / [太原节点路由数据](https://stat.ripe.net/data/network-info/data.json?resource=218.26.162.114) / [LibreSpeed 节点格式](https://github.com/librespeed/speedtest-cli#use-a-custom-backend-server-list)

## 首版对照方法

1. iPhone 和电脑连同一个 Wi-Fi，在相近时间分别跑检测，每次记录设备、时间、连接方式、是否有 VPN、出口类型和测速节点。只有节点一致的样本用于计算差异。
2. 在电脑上运行同一 `NetworkQualityService`，使用相同的请求大小、顺序和算法。记录两个报告的延迟、抖动和 Mbps，并检查两侧 IP 和 ASN。
3. 在 iPhone 上用蜂窝网络重跑。还需在仅一种 IP 可用、VPN 分流、测速时换网络和取消后重跑的情况下记录结果。检查用户看到的不可用原因是否与实际情况相符。

## 三网回程

`QualityReturnRouteService.trace(toPublicTarget:)` 以一个公开的 IPv4 或 IPv6 地址为目标，请 [Globalping](https://github.com/jsdelivr/globalping/blob/master/public/v1/spec.yaml) 从中国大陆的电信（AS4134）、联通（AS4837）和移动（AS9808）各选择一个在线节点，执行 ICMP 路由追踪。结果带运营商、节点城市、地址类型、逐跳往返时延和目标是否回应。没有回应的一跳保持原来的位置。一个运营商缺少结果时保留其他运营商已取得的记录。

[Globalping 会公开测量目标和结果](https://globalping.io/terms/terms-of-use.md)。此服务只用于可以公开的目标，由调用方单独发起，常规网络检测不调用。测到的是远端到公网地址的线路。共享地址、路由器、防火墙和 VPN 都可能使远端只能测到部分线路。

界面入口在网络检测的「三网线路 → 回程线路」，检测进行中不显示。读者手动填写或点选本次检测的出口地址，确认公开后才开始。界面通过 `ReturnRouteTesting` 调用，离线界面测试使用 `SampleReturnRouteTester`：电信、联通有结果，移动没有节点。

## 进阶检测与离线跑分

- 用 `AdvancedNetworkQualityService().run(for:)` 对已有首版报告补测。预览用 `AdvancedQualityExamples.partial`。五个网站分别发一次 HTTPS GET，报告区分页面可访问、重定向、HTTP 451、超时和其他失败。HTTP 403 只记录服务端拒绝。
- 邮件测试尝试连接 `portquiz.net` 的 TCP 25，区分成功、拒绝、超时和其他错误。STUN 检测通过同一个 IPv4 UDP 端口，向服务器的不同 IP 和端口发请求，记录观测到的映射地址、端口和 RFC 5780 映射行为。先测 Nextcloud，查不全时再测小米，两次尝试分别返回。
- IP 信誉从 Spamhaus DROP 和 Blocklist.de 下载公开名单，在手机上分别比对已有的 IPv4 和 IPv6。`notListed` 表示对应名单未收录该地址。各来源的结果、失败原因和查询时间分开显示。
- 三网使用 NextTrace 的北京电信、北京联通、广州移动 IPv4 节点。向每个节点发 5 个 ICMP 请求计算丢包。逐跳追踪最多 24 跳，一跳超时后继续测。报告记录缺少回应的位置、目标和实际发包数。对最多 12 个不同的公网沿途地址查 IPinfo，查到时附上网络名称和 ASN。这是从手机发出的线路，NodeQuality 还会检测反方向线路。
- 用 `HardwareQualityService.run(onProgress:)` 在 iPhone 上离线运行。取消和首版检测的用法一样，预览用 `HardwareQualityExamples.completed`。CPU 单核和多核使用同一批固定工作量。存储顺序读写后复用同一测试文件做随机读写。写入和读取都请系统绕过文件缓存，完成或取消后删除测试文件。结果以 MiB/s 为单位，带系统版本、设备型号、低电量模式和温度状态。

[RFC 5780](https://www.rfc-editor.org/info/rfc5780/) / [Nextcloud STUN](https://github.com/nextcloud/spreed/blob/main/lib/Config.php) / [PortQuiz](http://portquiz.net/) / [Spamhaus DROP](https://www.spamhaus.org/blocklists/do-not-route-or-peer/) / [Blocklist.de](https://www.blocklist.de/en/export.html)

## 公网 IP 风险和 BGP 路由

调用 `QualityIPDetailsService.run(for:)` 可从已有网络报告补查每个已测得的 IPv4、IPv6 出口。每个地址分别返回两个来源的结果和查询时间。没有测到某类地址时，该类地址不发请求。一键检测在测得公网地址后运行这一步，报告的「IP 类型与路由」按地址列出 IPQuery 的类型和分值、RIPEstat 的地址段和发布网络。重试只替换失败的查询，已取得的结果保留。分享时如隐藏 IP，地址段也不写入，只保留发布网络。

- [RIPEstat Network Info](https://stat.ripe.net/docs/data-api/api-endpoints/network-info.html) 返回 RIPE RIS 观察到的匹配地址段和宣布该地址段的 ASN。可有多个 ASN。空结果表示该来源没有看到公告，连接失败会单独返回。查询时间为 App 发请求的时间，RIPE RIS 数据本身按来源更新。
- [IPQuery](https://ipquery.io/developers/api) 返回它自己的 0–100 分值和网络分类。VPN、代理、Tor、机房和蜂窝为独立标记。未匹配和字段缺失分别保留，分值不是恶意活动的概率。IPQuery 的结果与已有两家黑名单分开。

两家服务都会收到查询目标的完整公网地址。联网对照使用公开测试地址 `1.1.1.1` 和 `2606:4700:4700::1111`，RIPEstat 均返回 AS13335，IPQuery 均返回数据中心分类。

## 实机验证记录

iPhone 17，iOS 27.3，2026-11-17。手机离线时，网络检测返回 `offline`。连续三轮 CPU 和存储测试均完成，均无文件清理错误。设备温度状态始终为 `fair`，低电量模式关闭。下表数字四舍五入到整数。

| 轮次 | CPU（MiB/s） | 写入（MiB/s） | 读取（MiB/s） |
| --- | ---: | ---: | ---: |
| 1 | 2777 | 265 | 1287 |
| 2 | 3009 | 232 | 933 |
| 3 | 2575 | 203 | 941 |

Mac 在 2026-11-18 用同一份代码经 Wi-Fi 测得 TPE 节点下载 4.48 Mbps、上传 4.56 Mbps、时延 376.52 ms、抖动 401.32 ms，五个时延样本均有效。IPv4 和归属返回成功，IPv6 请求在建立加密连接时失败。TCP 25 可连接。两个 IP 名单先前一次请求成功，本次均超时。Nextcloud 返回了映射地址和端口，服务器给出的备用地址与主地址相同，小米请求超时，本次未取得 NAT 分类。三网均有目的地址回应，逐跳结果仍待真机确认。

待测场景包括 iPhone 与电脑在同一 Wi-Fi 上对照、蜂窝网络、只有一种 IP 可用、VPN 分流和真机测速时换网。

## 流媒体样片检查

`QualityStreamingService.run()` 从当前网络请求五个平台的公开样片。Netflix、Disney+ 和 Prime Video 检查页面是否明确对应请求的片名。YouTube 和 TikTok 检查嵌入接口是否为指定视频返回元数据。每项记录样片、请求地址、时间、HTTP 状态和可取得的连接地址类型。各平台独立返回结果。

HTTP 401、451、重定向和超时分别记录。403、404、返回首页或挑战页面时保留无法判断。公共片名和嵌入元数据只说明本次取得了哪种信息。付费内容实际播放和地区目录还需要测试账号、可复现的受限样片或平台提供的播放结果。当前一键检测仍使用已有的网站访问检查。

另外，调用方提供 YouTube Data API 密钥、视频编号和国家代码时，`checkYouTubeRegion(videoID:countryCode:apiKey:)` 可以查该片已发布的允许或限制规则。未发布地区规则和找不到视频应分别记录。国家代码由调用方提供，结果说明规则对该国家的判断。密钥仅随请求头传给 Google。

[YouTube 地区规则](https://developers.google.com/youtube/data/reference/rest/v3/videos#contentDetails.regionRestriction) / [Netflix 地区说明](https://help.netflix.com/en/node/125345) / [YouTube 嵌入播放器规则](https://developers.google.com/youtube/terms/required-minimum-functionality) / [TikTok 嵌入接口](https://developers.tiktok.com/docs/en/embed-videos)

`QualityStreamingService.playbackCheck(for:)` 为 YouTube 和 TikTok 样片生成一次播放检查。调用方把同一样片的官方可见播放器事件传给检查对象。YouTube 使用 IFrame Player API 的状态、播放时间和错误回调。TikTok 使用该样片 iframe 的消息，调用方先检查事件来源是该 iframe。只有播放器进入播放状态，并且播放时间持续前进，才得到已播放。缓冲、中途跳转、自动播放被阻止和播放器报错分别处理。这项检查适用于指定样片。

[YouTube 播放器 API](https://developers.google.com/youtube/iframe_api_reference) / [TikTok 播放器 API](https://developers.tiktok.com/docs/en/embed-player)

App 在网络检测的“常用服务”一节末尾放了“流媒体”入口，检测进行中时隐藏。页面通过 `NodeSeekCore` 的 `StreamingChecking` 调用以上服务，界面测试用 `SampleStreamingChecker`。

- 样片一节逐个平台显示样片名和取得的信息。非 200 的 HTTP 状态写在样片名后面。
- 播放器一节在弹出页里用 `WKWebView` 打开官方播放器，静音自动播放。网页的基础地址为 `https://` 加小写的 Bundle ID，作为 YouTube 要求的 Referer。YouTube 每 250 ms 读一次 `getCurrentTime()`。TikTok 只转发来源为该样片 iframe、且 origin 为 `https://www.tiktok.com` 的消息。TikTok 的 `WKWebView` 在默认 User-Agent 后加上 `Safari/604.1`，和 Mobile Safari 一致：缺少这个标识时，TikTok 服务器多数时候返回错误 2001。播放器里的外链在浏览器中打开。30 秒内没有结果记为超时，提前关闭记为已取消。
- YouTube 地区规则的国家代码默认取本次检测的出口归属，可以修改。API 密钥只存在本机钥匙串，离线界面测试只存在内存里。
