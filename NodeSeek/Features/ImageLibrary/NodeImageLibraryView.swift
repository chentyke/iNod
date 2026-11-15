import NodeSeekCore
import NodeSeekClient
import SwiftUI
import PhotosUI

struct NodeImageLibraryView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var client = NodeImageClient()
    @State private var key = ""
    @State private var savedKey = ""
    @State private var initialized = false
    @State private var images: [HostedImage] = []
    @State private var item: PhotosPickerItem?
    @State private var prepared: PreparedUploadImage?
    @State private var lastUpload: HostedImage?
    @State private var deleting: HostedImage?
    @State private var confirmsDelete = false
    @State private var confirmsKeyRotation = false
    @State private var loading = false
    @State private var preparing = false
    @State private var updating = false
    @State private var error: String?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                SecureField("NodeImage API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Button("保存密钥") { Task { await saveKey() } }.disabled(updating || loading || !NodeImageAPI.validKey(key.trimmingCharacters(in: .whitespacesAndNewlines)))
                Button(savedKey.isEmpty ? "连接 NodeImage" : "同步密钥") {
                    Task { await syncKey(regenerating: false) }
                }.disabled(updating || loading || preparing)
                Button("更新密钥") { confirmsKeyRotation = true }.disabled(updating || loading || preparing)
                if !savedKey.isEmpty { Button("移除本机密钥", role: .destructive) { removeKey() }.disabled(loading || updating) }
            } header: { Text("图床账号") } footer: { Text("密钥只保存在这台设备，并按论坛账号分别保存。上传的图片通过公开链接访问。") }
            .alert("更新 NodeImage 密钥？", isPresented: $confirmsKeyRotation) {
                Button("更新密钥", role: .destructive) { Task { await syncKey(regenerating: true) } }
                Button("取消", role: .cancel) {}
            } message: { Text("更新后旧密钥会失效，使用旧密钥的工具也需要换成新密钥。") }

            if !savedKey.isEmpty {
                Section {
                    PhotosPicker("选择图片", selection: $item, matching: .images).disabled(updating || preparing)
                    if preparing { ProgressView("正在处理图片") }
                    if let prepared {
                        Image(decorative: prepared.image, scale: 1).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                        Button(updating ? "上传中…" : "上传图片") { Task { await upload() } }.disabled(updating || loading || preparing)
                    }
                    if let lastUpload {
                        Text("图片已上传").foregroundStyle(Color.seekGreen)
                        imageActions(lastUpload)
                    }
                } header: { Text("上传") } footer: { Text("图片最长边缩小到 2048 像素，去掉照片元数据后上传。失败时不会自动重新上传。") }
                Section("已上传图片") {
                    if loading { ProgressView("正在读取图片") }
                    if !loading, images.isEmpty { ContentUnavailableView("暂无图片", systemImage: "photo.on.rectangle", description: Text("选择一张图片并上传，或下拉刷新。")) }
                    ForEach(images) { image in
                        VStack(alignment: .leading, spacing: 12) {
                            ForumImageView(url: image.url, alt: image.filename).frame(maxHeight: 240)
                            Text(image.filename).font(.subheadline).lineLimit(2)
                            if let date = image.uploadedAt { ForumDateText(value: date).font(.caption).foregroundStyle(.secondary) }
                            imageActions(image)
                        }.padding(.vertical, 10)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除图片", role: .destructive) { deleting = image; confirmsDelete = true }.disabled(updating || loading)
                        }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red); if !savedKey.isEmpty { Button("刷新已上传列表") { Task { await load() } }.disabled(loading || updating) } } }
            if let message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
        }
        .seekGroupedList().navigationTitle("图片上传与管理").navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(updating)
        .task {
            guard !initialized else { return }; initialized = true
            do { savedKey = try NodeImageKeyStore.read(userID: userID); key = savedKey; if !savedKey.isEmpty { await load() } }
            catch { self.error = error.localizedDescription }
        }
        .task(id: item) {
            guard let item else { return }; prepared = nil; lastUpload = nil; preparing = true; error = nil
            defer { preparing = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw SiteError.invalidResponse }
                let result = try await Task.detached(priority: .userInitiated) { try UploadImageProcessor.prepare(data) }.value
                try Task.checkCancellation(); prepared = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .refreshable { await load() }
        .confirmationDialog("删除这张图片？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("删除图片", role: .destructive) { if let image = deleting { Task { await delete(image) } } }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("已发布帖子中的这张图片也会无法显示，删除后不能恢复。") }
    }

    private func imageActions(_ image: HostedImage) -> some View {
        ShareLink("分享链接", item: image.url).font(.subheadline).frame(minHeight: 44)
    }

    private func saveKey() async {
        guard !loading, !updating, account.user?.id == userID else { return }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NodeImageAPI.validKey(value) else { return }
        do { try NodeImageKeyStore.save(value, userID: userID); savedKey = value; key = value; images = []; message = "密钥已保存。"; await load() }
        catch { self.error = error.localizedDescription }
    }

    private func syncKey(regenerating: Bool) async {
        guard !loading, !updating, !preparing, account.user?.id == userID else { return }
        updating = true
        error = nil
        message = nil
        defer { updating = false }
        do {
            let updated = try await account.syncNodeImageKey(userID: userID, regenerating: regenerating)
            guard !Task.isCancelled, account.user?.id == userID else { return }
            if updated != savedKey {
                images = []
                lastUpload = nil
            }
            savedKey = updated
            key = updated
            message = regenerating ? "密钥已更新。" : "密钥已同步。"
            updating = false
            await load()
        } catch {
            if !Task.isCancelled, account.user?.id == userID { self.error = error.localizedDescription }
        }
    }

    private func removeKey() {
        do { try NodeImageKeyStore.save("", userID: userID); key = ""; savedKey = ""; images = []; prepared = nil; item = nil; lastUpload = nil; error = nil; message = "本机密钥已移除。" }
        catch { self.error = error.localizedDescription }
    }

    private func load() async {
        guard !savedKey.isEmpty, !loading, !updating, account.user?.id == userID else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            let result = try await client.images(key: savedKey)
            try Task.checkCancellation()
            guard account.user?.id == userID else { return }
            images = result
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func upload() async {
        guard let prepared, !updating, !loading, account.user?.id == userID else { return }
        updating = true; error = nil; message = nil
        defer { updating = false }
        do {
            let result = try await client.upload(png: prepared.png, key: savedKey)
            guard account.user?.id == userID else { return }
            lastUpload = result; self.prepared = nil; item = nil
            if !result.id.isEmpty { images.removeAll { $0.id == result.id }; images.insert(result, at: 0) }
        } catch { self.error = error.localizedDescription + " 上传结果不确定时，请先刷新已上传列表检查。" }
    }

    private func delete(_ image: HostedImage) async {
        guard !updating, !loading, account.user?.id == userID else { return }
        updating = true; error = nil; defer { updating = false; deleting = nil }
        do {
            try await client.delete(image, key: savedKey)
            guard account.user?.id == userID else { return }
            images.removeAll { $0.id == image.id }
            if lastUpload?.id == image.id { lastUpload = nil }
            message = "图片已删除。"
        } catch { self.error = error.localizedDescription }
    }
}
