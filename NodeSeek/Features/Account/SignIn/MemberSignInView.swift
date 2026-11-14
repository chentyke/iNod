import NodeSeekClient
import SwiftUI

struct MemberSignInView: View {
    @Environment(AccountSession.self) private var account
    @State private var showsSignIn = false
    var body: some View {
        Group {
            if account.signInStatus == .signedOut {
                ContentUnavailableView {
                    Label("请先登录", systemImage: "person.crop.circle")
                } actions: {
                    Button("登录") { showsSignIn = true }.buttonStyle(.seekPill)
                }
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
}
