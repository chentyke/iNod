import CoreImage.CIFilterBuiltins
import NodeSeekCore
import NodeSeekClient
import SwiftUI
import UIKit

struct TwoFactorView: View {
    @Environment(AccountSession.self) private var account
    @Environment(\.dynamicTypeSize) private var typeSize
    let userID: Int
    @State private var loader = ResourceLoader<OTPStatus>()
    @State private var password = ""
    @State private var setup: OTPSetup?
    @State private var qrImage: CGImage?
    @State private var copiedSecret = false
    @State private var confirmsChange = false

    var body: some View {
        ResourceContent(loader: loader, retry: { await load(force: true) }) { status in
            List {
                Section {
                    VStack(alignment: .leading, spacing: AccountSettingsMetrics.blockSpacing) {
                        let headerLayout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                            : AnyLayout(HStackLayout(alignment: .center, spacing: AccountSettingsMetrics.rowSpacing))
                        headerLayout {
                            HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                                SeekIconTile(
                                    symbol: status.enabled ? "lock.shield.fill" : "lock.shield",
                                    tint: status.enabled ? .seekGreen : .seekInk
                                )
                                Text(status.enabled ? "双因素验证已开启" : "双因素验证未开启")
                                    .font(.headline)
                                    .foregroundStyle(Color.seekInk)
                            }
                            if !typeSize.isAccessibilitySize {
                                Spacer(minLength: 8)
                            }
                            SettingsStatusPill(
                                text: status.enabled ? "已保护" : "未开启",
                                active: status.enabled
                            )
                        }

                        Text("开启后，每次登录除了账号密码外，还需输入验证器 App 生成的动态验证码。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("two-factor-status-card")
                    .listRowInsets(AccountSettingsMetrics.cardInsets(hasBottomCapsule: false))
                    .listRowBackground(Color.seekCard)
                    .listRowSeparator(.hidden)
                }

                if let setup {
                    Section {
                        if let image = qrImage {
                            Image(decorative: image, scale: 1)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 200)
                                .padding(14)
                                .background(Color.white, in: .rect(cornerRadius: 16))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .listRowBackground(Color.seekCard)
                                .accessibilityLabel("双因素验证密钥二维码")
                        }

                        HStack(spacing: AccountSettingsMetrics.rowSpacing) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("密钥")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(setup.secret)
                                    .font(.body.monospaced())
                                    .foregroundStyle(Color.seekInk)
                                    .textSelection(.enabled)
                                    .privacySensitive()
                            }
                            Spacer(minLength: 8)
                            Button {
                                UIPasteboard.general.string = setup.secret
                                copiedSecret = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedSecret ? "checkmark" : "doc.on.doc")
                                        .accessibilityHidden(true)
                                    Text(copiedSecret ? "已复制" : "复制")
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(copiedSecret ? Color.seekGreen : Color.seekInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.seekTray, in: .capsule)
                            }
                            .buttonStyle(.seekRow)
                            .accessibilityIdentifier("two-factor-copy-secret")
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.seekCard)

                        if let url = URL(string: setup.uri), url.scheme?.lowercased() == "otpauth" {
                            Link(destination: url) {
                                SeekRowLabel(
                                    title: "在验证器 App 中打开",
                                    symbol: "key.viewfinder",
                                    opensExternally: true
                                )
                            }
                            .settingsRowStyle(alignSeparator: false)
                        }
                    } header: {
                        SeekSectionTitle(title: "保存到验证器", detail: "仅显示一次")
                    } footer: {
                        Text("请先在验证器中保存密钥并确认能生成验证码。关闭此页面后，iNod 不会保留密钥。")
                    }
                }

                Section {
                    SecureField("输入当前密码以确认", text: $password)
                        .textContentType(.password)
                        .frame(minHeight: 36)
                        .disabled(loader.updating)
                        .accessibilityIdentifier("two-factor-password-field")
                        .listRowBackground(Color.seekCard)
                } header: {
                    SeekSectionTitle(title: status.enabled ? "关闭验证" : "启用验证")
                }

                Section {
                    SettingsActionPill(
                        title: status.enabled ? "关闭双因素验证" : "启用并生成密钥",
                        symbol: status.enabled ? "lock.open" : "qrcode",
                        busyTitle: "处理中…",
                        isBusy: loader.updating,
                        primary: !status.enabled,
                        destructive: status.enabled,
                        surface: .seekCard
                    ) {
                        confirmsChange = true
                    }
                    .disabled(loader.updating || password.isEmpty)
                    .accessibilityIdentifier("two-factor-action-button")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("双因素验证")
        .interactiveDismissDisabled(loader.updating)
        .task { await load() }
        .alert(
            loader.value?.enabled == true ? "关闭双因素验证？" : "启用双因素验证？",
            isPresented: $confirmsChange
        ) {
            Button(
                loader.value?.enabled == true ? "关闭" : "启用",
                role: loader.value?.enabled == true ? .destructive : nil
            ) {
                Task { await change() }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(
                loader.value?.enabled == true
                    ? "关闭后登录将不再要求动态验证码。"
                    : "启用后立即生效，请在离开前把密钥保存到验证器。"
            )
        }
        .onChange(of: setup?.uri) { _, uri in
            copiedSecret = false
            qrImage = uri.flatMap(qr)
        }
        .onDisappear {
            password = ""
            setup = nil
            qrImage = nil
            copiedSecret = false
        }
    }

    private func load(force: Bool = false) async {
        await loader.load(account.website, .otpStatus, force: force, allowingStale: false)
    }

    private func change() async {
        guard !loader.updating, let status = loader.value else { return }
        loader.updating = true
        defer { loader.updating = false }
        do {
            if status.enabled {
                let _: ReactionResponse = try await account.website.perform(
                    .otp(enable: false, password: password),
                    userID: userID
                )
                setup = nil
            } else {
                setup = try await account.website.perform(
                    .otp(enable: true, password: password),
                    userID: userID
                )
            }
            password = ""
            await load(force: true)
        } catch {
            loader.error = LoadFailure(error)
        }
    }

    private func qr(_ value: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else {
            return nil
        }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
