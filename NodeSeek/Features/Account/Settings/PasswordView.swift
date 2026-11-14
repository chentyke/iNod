import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct PasswordView: View {
    @Environment(AccountSession.self) private var account
    let userID: Int
    @State private var old = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var message: String?
    @State private var success = false
    var body: some View {
        Form {
            Section {
                SecureField("当前密码",text:$old).textContentType(.password)
                SecureField("新密码",text:$password).textContentType(.newPassword)
                SecureField("再次输入新密码",text:$confirmation).textContentType(.newPassword)
            } footer: { Text("官网要求 6–18 位，可以使用英文字母、数字、点、短横线和下划线。") }
            if let message { Section { Label(message,systemImage:success ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(success ? Color.seekGreen : .red) } }
            Section { Button(busy ? "保存中…" : "保存新密码") { Task { await save() } }.disabled(busy || old.isEmpty || password.firstMatch(of:/^[0-9a-zA-Z.\-_]{6,18}$/) == nil || password != confirmation) }
            Section("忘记当前密码") { OfficialSettingsLink(title:"通过邮箱或短信重设",anchor:"security",description:"验证码和人机验证由官网完成。") }
        }.disabled(busy).seekCanvas().listSectionSpacing(20).navigationTitle("修改密码").navigationBarTitleDisplayMode(.inline).toolbar(.hidden,for:.tabBar)
        .onDisappear { old = ""; password = ""; confirmation = "" }
    }
    private func save() async {
        guard !busy else { return }; busy = true; message = nil; defer { busy = false }
        do {
            let _: ReactionResponse = try await account.website.perform(.changePassword(old: old, new: password), userID: userID)
            old = ""; password = ""; confirmation = ""; success = true; message = "密码已更新。"
        } catch { success = false; message = error.localizedDescription }
    }
}
