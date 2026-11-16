import NodeSeekClient
import SwiftUI
import PhotosUI

struct AvatarEditorView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var item: PhotosPickerItem?
    @State private var avatar: PreparedAvatar?
    @State private var busy = false
    @State private var error: String?
    @State private var success = false
    var body: some View {
        Form {
            Section {
                Group {
                    if let avatar { Image(decorative:avatar.image,scale:1).resizable().scaledToFit().frame(width:100,height:100).clipShape(.circle) }
                    else { AvatarView(name:account.user?.name ?? "",url:account.user?.avatarURL,size:100) }
                }.frame(maxWidth:.infinity).padding(.vertical,24)
                PhotosPicker("选择照片",selection:$item,matching:.images).disabled(busy)
            } footer: { Text("照片中央的正方形区域会作为头像，保存前可以在上方预览。") }
            Section { Button(busy ? "上传中…" : "保存头像") { Task { await upload() } }.disabled(avatar == nil || busy) }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if success { Section { Label("头像已更新",systemImage:"checkmark.circle").foregroundStyle(Color.seekGreen) } }
        }.seekCanvas().listSectionSpacing(20).navigationTitle("修改头像").navigationBarTitleDisplayMode(.inline).toolbar(.hidden,for:.tabBar)
        .task(id:item) {
            guard let item else { return }; error = nil; success = false
            do {
                guard let data = try await item.loadTransferable(type:Data.self) else { throw SiteError.invalidResponse }
                let prepared = try await Task.detached(priority:.userInitiated) { try AvatarProcessor.prepare(data) }.value
                try Task.checkCancellation(); avatar = prepared
            } catch { if !Task.isCancelled { self.error = SiteError.displayMessage(for: error) } }
        }
    }
    private func upload() async {
        guard !busy,let avatar else { return }; busy = true; defer { busy = false }; error = nil
        do {
            try await account.website.uploadAvatar(avatar.png,userID:userID)
            self.avatar = nil; item = nil; success = true
            account.avatarDidChange()
            await account.refresh(force:true)
        } catch { self.error = SiteError.displayMessage(for: error) }
    }
}
