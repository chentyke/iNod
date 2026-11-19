import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct PasswordView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.dynamicTypeSize) private var typeSize
    let userID: Int
    @State private var old = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var message: String?
    @State private var success = false

    private var validation: PasswordValidation {
        PasswordValidation(
            currentPassword: old,
            newPassword: password,
            confirmation: confirmation
        )
    }

    var body: some View {
        List {
            if let message {
                Section {
                    SettingsFeedbackRow(message: message, isSuccess: success)
                        .listRowBackground(Color.seekCard)
                }
            }

            Section {
                passwordRow(
                    title: "当前密码",
                    placeholder: "输入当前密码",
                    text: $old,
                    contentType: .password,
                    identifier: "password-current-field"
                )

                passwordRow(
                    title: "新密码",
                    placeholder: "6–18 位字符",
                    text: $password,
                    contentType: .newPassword,
                    identifier: "password-new-field"
                )

                passwordRow(
                    title: "确认密码",
                    placeholder: "再次输入新密码",
                    text: $confirmation,
                    contentType: .newPassword,
                    identifier: "password-confirm-field"
                )
            } header: {
                SeekSectionTitle(title: "更换密码")
            } footer: {
                if let issue = validation.issueMessage {
                    Text(issue)
                        .foregroundStyle(.red)
                } else {
                    Text("官网要求 6–18 位，可使用英文字母、数字、点（.）、短横线（-）和下划线（_）。")
                }
            }

            Section {
                SettingsActionPill(
                    title: "保存新密码",
                    symbol: .inkSavePassword,
                    busyTitle: "正在保存…",
                    isBusy: busy
                ) {
                    Task { await save() }
                }
                .disabled(busy || !validation.canSubmit)
                .accessibilityIdentifier("password-save-button")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                OfficialSettingsLink(
                    title: "通过邮箱或短信重设",
                    symbol: .inkResetPassword,
                    anchor: "security",
                    description: "验证码与人机验证在官网完成"
                )
                .accessibilityIdentifier("password-reset-link")
                .settingsRowStyle(alignSeparator: false)
            } header: {
                SeekSectionTitle(title: "忘记当前密码")
            }
        }
        .seekGroupedList()
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .navigationTitle("修改密码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: old) { clearErrorMessage() }
        .onChange(of: password) { clearErrorMessage() }
        .onChange(of: confirmation) { clearErrorMessage() }
        .onDisappear {
            old = ""
            password = ""
            confirmation = ""
        }
    }

    @ViewBuilder
    private func passwordRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType,
        identifier: String
    ) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .foregroundStyle(Color.seekInk)
                    SecureField(placeholder, text: text)
                        .textContentType(contentType)
                        .accessibilityIdentifier(identifier)
                }
            } else {
                HStack(spacing: 12) {
                    Text(title)
                        .foregroundStyle(Color.seekInk)
                        .frame(width: 76, alignment: .leading)
                    SecureField(placeholder, text: text)
                        .textContentType(contentType)
                        .accessibilityIdentifier(identifier)
                }
            }
        }
        .frame(minHeight: 38)
        .listRowBackground(Color.seekCard)
    }

    private func clearErrorMessage() {
        if !success { message = nil }
    }

    private func save() async {
        guard !busy, validation.canSubmit else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let _: ReactionResponse = try await account.website.perform(
                .changePassword(old: old, new: password),
                userID: userID
            )
            old = ""
            password = ""
            confirmation = ""
            success = true
            message = "密码已更新。"
        } catch {
            success = false
            message = SiteError.displayMessage(for: error)
        }
    }
}
