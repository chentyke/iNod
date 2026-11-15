import NodeSeekCore
import NodeSeekClient
import SwiftUI
import WebKit

struct SignInView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var session = SignInSession()
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var otpSession: String?
    @State private var busy = false
    @State private var error: String?
    @State private var showsWebsite = false

    var body: some View {
        NavigationStack {
            Form {
                if otpSession == nil {
                    Section("账号") {
                        TextField("用户名或邮箱", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("密码", text: $password).textContentType(.password)
                    }
                    Section("人机验证") {
                        // The page centres the 65-point widget, so the row's padding stays even above and below it.
                        WebView(session.page).webViewContentBackground(.hidden).webViewBackForwardNavigationGestures(.disabled).frame(height: 72)
                            .overlay { if session.verification == "loading" { ProgressView("正在加载验证").font(.footnote) } }
                        if session.verification == "ready" { Label("验证完成", systemImage: "checkmark.circle").foregroundStyle(Color.seekGreen) }
                        if ["error", "expired"].contains(session.verification) {
                            Text(session.verification == "expired" ? "验证已过期，请重新验证。" : "验证暂时不可用，可以重试或使用官网登录。").font(.footnote).foregroundStyle(.secondary)
                            Button("重新验证") { Task { await session.resetVerification() } }
                        }
                    }
                } else {
                    Section {
                        Text("请输入验证器中的 6 位动态验证码。").font(.subheadline).foregroundStyle(.secondary)
                        TextField("动态验证码", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                    } header: { Text("双因素验证") }
                    Button("重新输入账号") { otpSession = nil; code = ""; error = nil }
                }
                Section {
                    Button(busy ? "登录中…" : "登录") { Task { await submit() } }
                        .buttonStyle(.seekPill)
                        .disabled(!canSubmit || busy)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button("使用官网登录、注册或找回密码", systemImage: "globe") { showsWebsite = true }
                } footer: { Text("密码只用于本次登录，App 不会保存密码。") }
            }
            .seekCanvas().navigationTitle(otpSession == nil ? "登录 NodeSeek" : "双因素验证").navigationBarTitleDisplayMode(.inline)
            .disabled(busy).interactiveDismissDisabled(busy)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
            .task { await session.monitor() }
            .sheet(isPresented: $showsWebsite) { WebsiteView(initialURL: NodeSeekRoute.origin.appending(path: "signIn.html")) }
            .onChange(of: account.isLoggedIn) { _, loggedIn in if loggedIn { dismiss() } }
            .onDisappear { password = ""; code = ""; otpSession = nil; session.clear() }
        }
    }

    private var canSubmit: Bool {
        if otpSession != nil { return code.count == 6 && code.allSatisfy { $0.isASCII && $0.isNumber } }
        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !session.token.isEmpty
    }

    private func submit() async {
        guard canSubmit, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        let isSecondFactor = otpSession != nil
        do {
            let result: SignInResponse
            if let otpSession { result = try await session.submit(body: ["otp_code": code, "otp_session": otpSession]) }
            else { result = try await session.submit(body: ["username": username.trimmingCharacters(in: .whitespacesAndNewlines), "password": password], verificationToken: session.token) }
            if !result.success {
                if result.isExpired { otpSession = nil; code = "" }
                throw SiteError.message(result.message ?? "登录未成功，请重试。")
            }
            if result.need2FA == true {
                guard let value = result.otpSession, !value.isEmpty else { throw SiteError.invalidResponse }
                otpSession = value; password = ""; code = ""
            } else {
                password = ""; code = ""; otpSession = nil
                await account.didSignIn()
                if account.isLoggedIn { dismiss() }
                else { error = account.error ?? "登录请求已完成，暂时无法确认登录状态，请重新读取。" }
            }
        } catch { self.error = error.localizedDescription }
        if !isSecondFactor { await session.resetVerification() }
    }
}
