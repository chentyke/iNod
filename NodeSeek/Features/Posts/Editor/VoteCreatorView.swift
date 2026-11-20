import NodeSeekClient
import SwiftUI

struct VoteCreatorView: View {
    let onCreated: (Int) -> Void
    @Environment(AccountSession.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var options = ["", ""]
    @State private var multiple = false
    @State private var isPublic = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmsCreation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("投票问题") { TextField("投票标题", text: $title) }
                Section("选项") {
                    ForEach(options.indices, id: \.self) { index in TextField("选项 \(index + 1)", text: $options[index]) }
                    Button("增加选项", image: .inkAddOption) { options.append("") }
                    if options.count > 2 { Button("移除最后一项", image: .inkRemoveOption, role: .destructive) { options.removeLast() } }
                }
                Section { Toggle("允许多选", isOn: $multiple); Toggle("公开参与者", isOn: $isPublic) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.disabled(busy).seekCanvas().listSectionSpacing(20).navigationTitle("创建投票").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button(busy ? "创建中…" : "创建") { confirmsCreation = true }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || options.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
            }
            .confirmationDialog("创建这个投票？", isPresented: $confirmsCreation, titleVisibility: .visible) {
                Button("创建投票") { Task { await create() } }; Button("取消", role: .cancel) { }
            } message: { Text("投票会立即保存到 NodeSeek，随后将链接插入草稿。") }
        }.interactiveDismissDisabled(busy)
    }
    private func create() async {
        guard let userID = account.user?.id, !busy else { return }; busy = true; defer { busy = false }; error = nil
        do {
            let id = try await account.website.createVote(title: title, multiple: multiple, isPublic: isPublic, options: options, userID: userID)
            onCreated(id); dismiss()
        } catch { self.error = SiteError.displayMessage(for: error) }
    }
}
