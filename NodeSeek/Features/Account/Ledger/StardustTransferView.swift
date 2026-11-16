import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct StardustTransferView: View {
    let userID: Int
    var recipient: MessageRecipient?
    var request: StardustRequest?
    @Environment(AccountSession.self) private var account
    @State private var member = ""
    @State private var amount = ""
    @State private var reference = "100"
    @State private var recipientName: String?
    @State private var confirmedID: Int?
    @State private var confirmedAmount: Int?
    @State private var confirmedReference: Int?
    @State private var confirmsTransfer = false
    @State private var busy = false
    @State private var message: String?
    @State private var success = false
    private var valid: Bool { MemberAddress.parse(member) != nil && (Int(amount) ?? 0) > 0 && (Int(reference) ?? 0) > 0 && MemberAddress.parse(member) != userID }
    var body: some View {
        Form {
            Section { LabeledContent("可用星尘",value:(account.user?.stardust ?? 0).formatted()) }
            Section("收款人") { TextField("用户编号或主页链接",text:$member).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(request != nil) }
            Section {
                TextField("转账数量",text:$amount).keyboardType(.numberPad).disabled(request != nil)
                TextField("Ref ID",text:$reference).keyboardType(.numberPad).disabled(request != nil)
            } header: { Text("转账信息") } footer: { Text("Ref ID 是官网用于区分转账用途的编号，默认 100。转账完成后不能撤回。") }
            Section { Button(busy ? "处理中…" : "核对收款人") { Task { await prepare() } }.disabled(busy || !valid) }
            if let message { Section { Text(message).foregroundStyle(success ? Color.seekGreen : .red) } }
        }.disabled(busy).seekCanvas().listSectionSpacing(20).navigationTitle("星尘转账").navigationBarTitleDisplayMode(.inline).toolbar(.hidden,for:.tabBar)
        .task { if let recipient { member = String(recipient.id) }; if let request { member = String(request.memberID); amount = String(request.amount); reference = String(request.reference) } }
        .confirmationDialog("确认转账？",isPresented:$confirmsTransfer,titleVisibility:.visible) {
            Button("转给 \(recipientName ?? "") \(confirmedAmount ?? 0) 个星尘") { Task { await send() } }; Button("取消",role:.cancel) { }
        } message: { Text("收款人：\(recipientName ?? "")（UID \(confirmedID ?? 0)）\n这笔转账不能撤回。") }
    }
    private func prepare() async {
        guard valid,!busy,let id = MemberAddress.parse(member),let amount = Int(amount),let reference = Int(reference) else { return }; busy = true; defer { busy = false }; message = nil
        do {
            guard amount <= (account.user?.stardust ?? 0) else { throw SiteError.message("星尘余额不足。") }
            if request?.once == true {
                let records: StardustRecords = try await account.website.load(.stardustPayment(memberID: id, reference: reference, peerID: userID), force: true)
                guard records.records.isEmpty else { throw SiteError.message("已经支付过这笔收款，请勿重复转账。") }
            }
            recipientName = try await account.website.prepareTransfer(recipientID: id, userID: userID)
            confirmedID = id; confirmedAmount = amount; confirmedReference = reference; confirmsTransfer = true
        } catch { success = false; message = SiteError.displayMessage(for: error) }
    }
    private func send() async {
        guard !busy,let id = confirmedID,let amount = confirmedAmount,let reference = confirmedReference,recipientName != nil else { return }; busy = true; defer { busy = false }; message = nil
        do {
            let _: ReactionResponse = try await account.website.perform(.transfer(recipientID: id, amount: amount, reference: reference), userID: userID)
            self.amount = ""; recipientName = nil; confirmedID = nil; success = true; message = "转账成功。"; await account.refresh(force:true)
        } catch { success = false; message = SiteError.displayMessage(for: error) }
    }
}
