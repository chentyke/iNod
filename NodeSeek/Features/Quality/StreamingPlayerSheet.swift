import NodeSeekCore
import SwiftUI
import WebKit

/// Plays one sample, muted, in its platform's visible official player and reports what the player did.
struct StreamingPlayerSheet: View {
    @State private var check: any StreamingPlaybackChecking
    @State private var startedAt = Date.now
    let report: (QualityResult<StreamingPlaybackOutcome>) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Long enough for a slow player to load and buffer, short enough that a stuck one does not hang the row.
    private static let timeout: Duration = .seconds(30)

    init(check: any StreamingPlaybackChecking, report: @escaping (QualityResult<StreamingPlaybackOutcome>) -> Void) {
        _check = State(initialValue: check)
        self.report = report
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    player
                        .aspectRatio(check.platform == .tikTok ? 9.0 / 16 : 16.0 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: check.platform == .tikTok ? 460 : nil)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.black)
                }
                Section {
                    QualityRow(title: "结果", subtitle: "样片 \(check.videoID)", status: check.result.status) {
                        if let outcome = check.result.value {
                            HStack(spacing: 6) { QualityDot(tint: outcome.tint); Text(outcome.title).foregroundStyle(.secondary) }
                        }
                    }
                    .accessibilityIdentifier("streaming.playback.result")
                } footer: {
                    Text(note)
                }
            }
            .seekGroupedList()
            .navigationTitle("\(check.platform.title) 试播").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("streaming.playback.done")
                }
            }
        }
        .task {
            // Nothing past the deadline counts; a player that has not proved playback by then timed out.
            try? await Task.sleep(for: check.isSample ? .milliseconds(Int(1200 * samplePace)) : Self.timeout)
            guard !Task.isCancelled else { return }
            receive(check.isSample ? .sampleFinished : .timeout)
        }
        .onDisappear {
            receive(.cancel)
        }
    }

    @ViewBuilder private var player: some View {
        if check.isSample {
            // Offline runs never load a real player.
            ZStack {
                Color.black
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle").font(.largeTitle)
                    Text("示例播放器，未联网").font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        } else {
            OfficialPlayerView(platform: check.platform, videoID: check.videoID) { receive($0) }
        }
    }

    private var note: String {
        let source = check.platform == .youTube ? "YouTube IFrame 播放器" : "TikTok 嵌入播放器"
        var lines = ["使用 \(source)，开始于 \(startedAt.formatted(date: .omitted, time: .standard))。"]
        switch check.result {
        case .measured(.played): lines.append("播放器进入播放状态，播放时间持续前进。")
        case .measured(.autoplayBlocked): lines.append("播放器报告自动播放被阻止，需要在播放器上点按才会开始播放。")
        case .measured(.playerError): lines.append("错误码由播放器给出，含义见平台的播放器文档。")
        case .unavailable: lines.append("30 秒内没有看到播放时间前进。")
        default: lines.append("播放时间持续前进后记为已播放，30 秒内没有前进记为超时。")
        }
        return lines.joined(separator: "\n")
    }

    private var samplePace: Double {
        let pace = UserDefaults.standard.double(forKey: "qualityPace")
        return pace > 0 ? pace : 1
    }

    private func receive(_ event: StreamingPlaybackEvent) {
        guard !check.result.status.isFinished else { return }
        check.receive(event)
        if check.result.status.isFinished { report(check.result) }
    }
}

// MARK: - Official player

/// A web view that hosts only the official player page and forwards its events after checking where they came from.
private struct OfficialPlayerView: UIViewRepresentable {
    let platform: StreamingPlatform
    let videoID: String
    let receive: (StreamingPlaybackEvent) -> Void

    /// YouTube asks embedded players in apps to identify themselves with a Referer made from the bundle ID.
    private static var origin: URL {
        URL(string: "https://\((Bundle.main.bundleIdentifier ?? "com.mie.nodeseek").lowercased())")!
    }

    func makeCoordinator() -> Coordinator { Coordinator(receive: receive) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        // Muted video may start by itself; sound would need a tap. This is what the check measures.
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.userContentController.add(context.coordinator, name: "player")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.host = Self.origin.host()
        if let page = page { view.loadHTMLString(page, baseURL: Self.origin) }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.receive = receive }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "player")
        view.stopLoading()
    }

    /// The page is built only from a checked ID, so nothing from outside lands in the script.
    private var page: String? {
        switch platform {
        case .youTube where YouTubeRegionCheck.isValidVideoID(videoID): Self.youTubePage(videoID)
        case .tikTok where videoID.wholeMatch(of: /[0-9]{1,24}/) != nil: Self.tikTokPage(videoID)
        default: nil
        }
    }

    private static let style = """
    <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
    <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#player{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
    """

    private static func youTubePage(_ id: String) -> String {
        """
        <!doctype html><html><head>\(style)</head><body><div id="player"></div><script>
        const post = m => window.webkit.messageHandlers.player.postMessage(m);
        let player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            width: '100%', height: '100%', videoId: '\(id)',
            playerVars: { autoplay: 1, mute: 1, playsinline: 1, rel: 0 },
            events: {
              onReady: e => {
                e.target.mute(); e.target.playVideo();
                setInterval(() => { const t = player.getCurrentTime(); if (typeof t === 'number') post({ type: 'position', value: t }); }, 250);
              },
              onStateChange: e => post({ type: 'state', value: e.data }),
              onError: e => post({ type: 'error', value: e.data }),
              onAutoplayBlocked: () => post({ type: 'autoplayBlocked' })
            }
          });
        }
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """
    }

    private static func tikTokPage(_ id: String) -> String {
        """
        <!doctype html><html><head>\(style)</head><body>
        <iframe id="player" src="https://www.tiktok.com/player/v1/\(id)?autoplay=1&force_muted=1&rel=0" allow="autoplay; fullscreen"></iframe>
        <script>
        const frame = document.getElementById('player');
        window.addEventListener('message', e => {
          // Only the sample's own iframe, served by TikTok, counts.
          if (e.source !== frame.contentWindow || e.origin !== 'https://www.tiktok.com') return;
          const data = typeof e.data === 'string' ? e.data : JSON.stringify(e.data);
          window.webkit.messageHandlers.player.postMessage({ type: 'tiktok', origin: e.origin, data: data });
        });
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var receive: (StreamingPlaybackEvent) -> Void
        var host: String?

        init(receive: @escaping (StreamingPlaybackEvent) -> Void) { self.receive = receive }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // Messages count only from the host page itself, never from a frame inside it.
            guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == host,
                  let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            let value = body["value"]
            let event: StreamingPlaybackEvent? = switch type {
            case "state": (value as? NSNumber).map { .youTubeState($0.intValue) }
            case "position": (value as? NSNumber).map { .youTubePosition($0.doubleValue) }
            case "error": (value as? NSNumber).map { .youTubeError($0.intValue) }
            case "autoplayBlocked": .youTubeAutoplayBlocked
            case "tiktok":
                if let data = body["data"] as? String, let origin = body["origin"] as? String { .tikTokMessage(Data(data.utf8), origin: origin) } else { nil }
            default: nil
            }
            if let event { receive(event) }
        }

        /// The host page stays put; links out of the player (such as "watch on YouTube") open in the browser.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // The player's own frames load freely; the host page only ever shows the page built here.
            guard action.targetFrame?.isMainFrame ?? true else { return .allow }
            guard let url = action.request.url else { return .cancel }
            if url.host() == host || url.scheme == "about" { return .allow }
            if url.scheme == "https", action.navigationType == .linkActivated || action.targetFrame == nil { await UIApplication.shared.open(url) }
            return .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, url.scheme == "https" { UIApplication.shared.open(url) }
            return nil
        }
    }
}
