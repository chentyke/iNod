import NodeSeekClient
import SwiftUI

/// Fills a page that has nothing to show because its request failed: what happened, what to do, and a way to do it.
///
/// One button carries the likely fix; at most one quieter link offers the next thing to try.
struct LoadFailureView: View {
    let failure: LoadFailure
    /// The title when the failure has no more specific one, such as "无法确认登录状态".
    var fallbackTitle: String?
    var isRetrying = false
    /// Offers the website even when the failure itself doesn't call for it, for a page the site can also show.
    var offersWebsite = false
    let retry: () -> Void
    var openWebsite: (() -> Void)?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: failure.systemImage)
                .font(.system(size: 40)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(title).font(.title3.bold()).foregroundStyle(Color.seekInk)
                Text(failure.advice).font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            // The title's line box carries about 5 points of air above its glyphs; the advice's barely any.
            .padding(.top, Self.gap - 5)
            .padding(.bottom, Self.gap)
            button(for: actions.primary, primary: true)
            if let secondary = actions.secondary {
                button(for: secondary, primary: false)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("load-failure")
    }

    private var title: String {
        if failure.kind == .other, let fallbackTitle { return fallbackTitle }
        return failure.title
    }

    private enum Action { case retry, website, settings }

    private var actions: (primary: Action, secondary: Action?) {
        let website: Action? = openWebsite == nil ? nil : .website
        switch failure.kind {
        case .verificationRequired: return website.map { ($0, .retry) } ?? (.retry, nil)
        case .offline: return (.retry, Self.settingsURL == nil ? nil : .settings)
        case .unreachable: return (.retry, website)
        default: return (.retry, offersWebsite ? website : nil)
        }
    }

    @ViewBuilder private func button(for action: Action, primary: Bool) -> some View {
        switch action {
        case .retry:
            if primary {
                Button(action: retry) {
                    if isRetrying { ProgressView().accessibilityLabel("正在重试") } else { Text("重试") }
                }
                .buttonStyle(.seekPill(fullWidth: false))
                .disabled(isRetrying)
            } else {
                Button("重试", action: retry).quietLink().disabled(isRetrying)
            }
        case .website:
            let label = failure.kind == .verificationRequired ? "打开官网完成验证" : "打开官网"
            if primary {
                Button(label) { openWebsite?() }.buttonStyle(.seekPill(fullWidth: false))
            } else {
                Button(label) { openWebsite?() }.quietLink()
            }
        case .settings:
            Button("打开设置") { if let url = Self.settingsURL { openURL(url) } }.quietLink()
        }
    }

    /// The app's page in Settings, where the reader can let it use mobile data. The Mac has no such page.
    private static var settingsURL: URL? {
        #if targetEnvironment(macCatalyst)
        nil
        #else
        URL(string: UIApplication.openSettingsURLString)
        #endif
    }

    private static let gap: CGFloat = 20
}

/// A one-line note above content that is still on screen after a refresh failed. It names the problem
/// and offers a retry without pushing the content away.
struct LoadFailureBanner: View {
    let failure: LoadFailure
    var isRetrying = false
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: failure.systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(failure.kind == .other ? failure.advice : failure.title)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                // The button's own side padding makes up the capsule's right inset, so the words sit
                // as far from the right edge as the symbol does from the left.
                Text("重试").fontWeight(.semibold)
                    .padding(.horizontal, Self.inset - Self.buttonInset)
                    .frame(minHeight: 36).contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .disabled(isRetrying)
        }
        .font(.footnote)
        .padding(.leading, Self.inset).padding(.trailing, Self.buttonInset)
        .frame(minHeight: 36)
        .background(Color.seekCard.opacity(0.7), in: .capsule)
        .overlay { Capsule().strokeBorder(Color.seekHairline.opacity(0.6), lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("load-failure-banner")
    }

    private static let inset: CGFloat = 14
    private static let buttonInset: CGFloat = 4
}

private extension View {
    func quietLink() -> some View {
        buttonStyle(.borderless).font(.subheadline).frame(minHeight: 44)
    }
}
