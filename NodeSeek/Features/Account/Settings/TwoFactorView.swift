import NodeSeekCore
import NodeSeekClient
import SwiftUI
import CoreImage.CIFilterBuiltins

struct TwoFactorView: View {
    @Environment(AccountSession.self) private var account
    let userID: Int
    @State private var loader = ResourceLoader<OTPStatus>()
    @State private var password = ""
    @State private var setup: OTPSetup?
    @State private var qrImage: CGImage?
    @State private var confirmsChange = false
    var body: some View {
        ResourceContent(loader:loader,retry:{ await load(force:true) }) { status in
            Form {
                Section {
                    Label(status.enabled ? "双因素验证已开启" : "双因素验证未开启",systemImage:status.enabled ? "lock.shield.fill" : "lock.shield").foregroundStyle(Color.seekGreen)
                    Text("开启后，登录需要验证器生成的动态验证码。").font(.subheadline).foregroundStyle(.secondary)
                }
                if let setup {
                    Section("保存到验证器") {
                        if let image = qrImage { Image(decorative:image,scale:1).interpolation(.none).resizable().scaledToFit().frame(maxWidth:240).frame(maxWidth:.infinity).padding(.vertical,12) }
                        Text(setup.secret).font(.body.monospaced()).textSelection(.enabled).privacySensitive()
                        if let url = URL(string:setup.uri) { Link("在验证器中打开",destination:url) }
                        Text("请先保存密钥。这个页面关闭后，App 不会保留密钥。").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section {
                    SecureField("当前密码",text:$password).textContentType(.password)
                    Button(loader.updating ? "处理中…" : (status.enabled ? "关闭双因素验证" : "启用并生成密钥"),role:status.enabled ? .destructive : nil) { confirmsChange = true }
                        .disabled(loader.updating || password.isEmpty)
                }
            }
        }.seekCanvas().listSectionSpacing(20).navigationTitle("双因素验证").task { await load() }
        .confirmationDialog(loader.value?.enabled == true ? "关闭双因素验证？" : "启用双因素验证？",isPresented:$confirmsChange,titleVisibility:.visible) {
            Button(loader.value?.enabled == true ? "关闭" : "启用",role:loader.value?.enabled == true ? .destructive : nil) { Task { await change() } }
            Button("取消",role:.cancel) { }
        } message: { Text(loader.value?.enabled == true ? "关闭后登录将不再要求动态验证码。" : "启用后立即生效，请在离开前把密钥保存到验证器。") }
        .onChange(of:setup?.uri) { _,uri in qrImage = uri.flatMap(qr) }
        .onDisappear { password = ""; setup = nil; qrImage = nil }
    }
    private func load(force: Bool = false) async { await loader.load(account.website, .otpStatus,force:force,allowingStale:false) }
    private func change() async {
        guard !loader.updating,let status = loader.value else { return }; loader.updating = true; defer { loader.updating = false }
        do {
            if status.enabled {
                let _: ReactionResponse = try await account.website.perform(.otp(enable: false, password: password), userID: userID); setup = nil
            } else { setup = try await account.website.perform(.otp(enable: true, password: password), userID: userID) }
            password = ""; await load(force:true)
        } catch { loader.error = LoadFailure(error) }
    }
    private func qr(_ value: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(value.utf8)
        guard let output = filter.outputImage?.transformed(by:CGAffineTransform(scaleX:8,y:8)) else { return nil }
        return CIContext().createCGImage(output,from:output.extent)
    }
}
