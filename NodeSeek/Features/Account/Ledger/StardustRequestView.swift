import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct StardustRequestView: View {
    let request: StardustRequest
    @Environment(AccountSession.self) private var account
    @State private var paymentCheck: (revision: Int, paid: Bool)?
    @State private var showsPayment = false
    @State private var error: String?

    private var paymentWasMade: Bool? {
        guard let paymentCheck, paymentCheck.revision == account.revision else { return nil }
        return paymentCheck.paid
    }

    private var paymentTitle: String {
        if account.signInStatus == .signedOut { return "登录后支付" }
        if request.once, paymentWasMade == true { return "已支付" }
        return "核对并支付"
    }

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Label(request.description,systemImage:"sparkles").font(.headline)
            Text("\(request.amount) 个星尘，收款人 UID \(request.memberID)").font(.subheadline).foregroundStyle(.secondary)
            if request.memberID == account.user?.id {
                NavigationLink("查看收款记录") { StardustHistoryView(memberID:request.memberID,initialReference:String(request.reference)) }
            } else {
                Button(paymentTitle) { showsPayment = true }
                    .buttonStyle(.seekPill)
                    .disabled(account.signInStatus != .signedIn || (request.once && paymentWasMade != false))
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("重试") { Task { await check() } }
            }
        }.padding(16).background(Color.seekTray.opacity(0.6),in:.rect(cornerRadius:16))
        .task(id:account.revision) { await check() }
        .sheet(isPresented:$showsPayment,onDismiss:{ Task { await check() } }) {
            if let owner = account.user { NavigationStack { StardustTransferView(userID:owner.id,request:request) } }
        }
    }
    private func check() async {
        error = nil
        paymentCheck = nil
        guard request.once, account.signInStatus == .signedIn,
              let owner = account.user, owner.id != request.memberID else { return }
        let revision = account.revision
        do {
            let result: StardustRecords = try await account.website.load(.stardustPayment(memberID: request.memberID, reference: request.reference, peerID: owner.id), force: true)
            try Task.checkCancellation()
            guard account.revision == revision else { return }
            paymentCheck = (revision, !result.records.isEmpty)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, account.revision == revision else { return }
            self.error = SiteError.displayMessage(for: error)
        }
    }
}
