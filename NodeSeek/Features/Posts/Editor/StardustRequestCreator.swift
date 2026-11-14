import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct StardustRequestCreator: View {
    let onCreated: (String) -> Void
    @Environment(AccountSession.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var reference = String(Int.random(in:100...100_000_099))
    @State private var description = "星尘收款"
    @State private var once = false
    var body: some View {
        NavigationStack {
            Form {
                Section("收款信息") {
                    TextField("说明",text:$description)
                    TextField("数量",text:$amount).keyboardType(.numberPad)
                    TextField("Ref ID",text:$reference).keyboardType(.numberPad)
                    Toggle("每人只需支付一次",isOn:$once)
                }
                Section { Text("插入后会显示原生收款按钮。对方需要核对收款人并确认，才会转出星尘。").font(.subheadline).foregroundStyle(.secondary) }
            }.seekCanvas().listSectionSpacing(20).navigationTitle("星尘收款").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("插入") {
                    if let id = account.user?.id,let amount = Int(amount),let reference = Int(reference) {
                        onCreated(StardustRequest(memberID:id,reference:reference,amount:amount,description:description,once:once).link); dismiss()
                    }
                }.disabled((Int(amount) ?? 0) <= 0 || (Int(reference) ?? 0) <= 0 || description.isEmpty) }
            }
        }
    }
}
