import NodeSeekClient
import SwiftUI

struct MemberSignInView: View {
    @Environment(AccountSession.self) private var account
    @State private var showsSignIn = false
    var body: some View {
        Group {
            if account.signInStatus == .signedOut {
                signInPrompt
            } else if let error = account.error, !account.isRefreshing {
                ContentUnavailableView {
                    Label("无法确认登录状态", systemImage: "exclamationmark.circle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await account.refresh(force: true) } }.buttonStyle(.seekPill)
                }
            } else {
                ProgressView("正在读取登录状态")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .seekCanvas()
        .task {
            if account.signInStatus == .unconfirmed { await account.refresh() }
        }
        .sheet(isPresented: $showsSignIn) { SignInView() }
    }

    /// Icon, words and button, with the same gap above and below the words. `ContentUnavailableView`
    /// leaves a wider gap before its actions than after its image.
    private var signInPrompt: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 44)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("请先登录").font(.title3.bold()).foregroundStyle(Color.seekInk)
                Text("登录后可以查看回复、提及和私信。").font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            // The title's line box carries about 5 points of air above its glyphs; the description's barely any.
            .padding(.top, Self.promptGap - 5)
            .padding(.bottom, Self.promptGap)
            Button("登录") { showsSignIn = true }.buttonStyle(.seekPill(fullWidth: false))
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let promptGap: CGFloat = 20
}
