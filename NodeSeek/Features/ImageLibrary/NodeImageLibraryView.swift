import NodeSeekCore
import NodeSeekClient
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct NodeImageLibraryView: View {
    let userID: Int

    @Environment(AccountSession.self) private var account
    private var preferences: NodeImageUploadPreferences

    @State private var key = ""
    @State private var savedKey = ""
    @State private var initialized = false
    @State private var images: [HostedImage] = []
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var pendingUploads: [PendingUpload] = []
    @State private var uploaded: [HostedImage] = []
    @State private var uploadedWhileLoading: [HostedImage] = []
    @State private var selectedIDs: Set<String>?
    @State private var pendingDeletion: [HostedImage] = []
    @State private var confirmsDelete = false
    @State private var confirmsKeyRotation = false
    @State private var importsFiles = false
    @State private var showsOptions = false
    @State private var loading = false
    @State private var preparing = false
    @State private var mutation: Mutation?
    @State private var error: String?
    @State private var message: String?

    private struct PendingUpload: Identifiable {
        let id = UUID()
        let image: PreparedUploadImage
    }

    private enum Mutation {
        case upload, delete, saveKey, syncKey, rotateKey
    }

    private let uploadLimit = 10
    private var remainingSlots: Int { uploadLimit - pendingUploads.count }
    private var working: Bool { mutation != nil }
    private var busy: Bool { working || loading || preparing }
    private var uploadBlocked: Bool { working || preparing }
    private var client: NodeImageClient { account.nodeImageHistory.client }
    private var ownsLibrary: Bool { account.user?.id == userID }
    private var selectedImages: [HostedImage] { images.filter { selectedIDs?.contains($0.id) == true } }
    private var imageOptions: UploadImageOptions { preferences.imageOptions(username: account.user?.name) }

    init(userID: Int) {
        self.userID = userID
        preferences = NodeImageUploadPreferences(userID: userID)
    }

    var body: some View {
        List {
            accountSection
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                    if !savedKey.isEmpty {
                        Button("刷新已上传列表") { Task { await load() } }.disabled(busy)
                    }
                }
            }
            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            if !savedKey.isEmpty {
                uploadSection
                if !uploaded.isEmpty { uploadResults }
                historySection
            }
        }
        .seekGroupedList()
        .navigationTitle("图片上传与管理")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(working)
        .sheet(isPresented: $showsOptions) {
            NodeImageUploadOptionsView(
                compressImages: preferences.$compressImages, compressionQuality: preferences.$compressionQuality,
                addWatermark: preferences.$addWatermark, watermarkWebsite: preferences.$watermarkWebsite,
                watermarkUsername: preferences.$watermarkUsername, copyAfterUpload: preferences.$copyAfterUpload,
                linkFormat: preferences.$linkFormat, autoDelete: preferences.$autoDelete, deleteDays: preferences.$deleteDays
            )
        }
        .fileImporter(isPresented: $importsFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): add(urls.map(NodeImageInput.file))
            case .failure(let error): self.error = SiteError.displayMessage(for: error)
            }
        }
        .task { await initialize() }
        .onChange(of: pickedPhotos) { _, photos in
            guard !photos.isEmpty else { return }
            pickedPhotos = []
            add(photos.map(NodeImageInput.photo))
        }
        .refreshable { await load() }
        .alert(
            pendingDeletion.count > 1 ? "删除这 \(pendingDeletion.count) 张图片？" : "删除这张图片？",
            isPresented: $confirmsDelete
        ) {
            Button("删除", role: .destructive) { Task { await deletePendingImages() } }
            Button("取消", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("删除后，已发布帖子中的这些图片也会无法显示。")
        }
    }

    private var accountSection: some View {
        Section("图床账号") {
            if mutation == .syncKey || mutation == .rotateKey {
                ProgressView(mutation == .rotateKey ? "正在更新密钥" : "正在同步密钥")
            }
            Button(savedKey.isEmpty ? "连接 NodeImage" : "同步密钥") {
                Task { await syncKey(regenerating: false) }
            }
            .disabled(!ownsLibrary || busy)
            Button("更新密钥") { confirmsKeyRotation = true }.disabled(!ownsLibrary || busy)
            DisclosureGroup("手动设置密钥") {
                SecureField("NodeImage 密钥", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                Button("保存密钥") { Task { await saveKey() } }
                    .disabled(busy || trimmedKey == savedKey || !NodeImageAPI.validKey(trimmedKey))
                if !savedKey.isEmpty {
                    Button("移除本机密钥", role: .destructive) { removeKey() }.disabled(busy)
                }
            }
        }
        .alert("更新 NodeImage 密钥？", isPresented: $confirmsKeyRotation) {
            Button("更新密钥", role: .destructive) { Task { await syncKey(regenerating: true) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("更新后旧密钥会失效，使用旧密钥的工具也需要换成新密钥。")
        }
    }

    private var uploadSection: some View {
        Section {
            HStack(spacing: 24) {
                PhotosPicker("相册", selection: $pickedPhotos, maxSelectionCount: max(1, remainingSlots),
                             selectionBehavior: .ordered, matching: .images)
                    .accessibilityLabel("选择图片")
                Button("文件", systemImage: "folder") { importsFiles = true }
                Spacer()
                PasteButton(supportedContentTypes: [.image]) { providers in
                    add(providers.map(NodeImageInput.provider))
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("粘贴图片")
            }
            .buttonStyle(.borderless)
            .disabled(working || preparing || remainingSlots == 0)
            .onDrop(of: [.image], isTargeted: nil) { providers in
                guard !working, !preparing, remainingSlots > 0, ownsLibrary else { return false }
                add(providers.map(NodeImageInput.provider))
                return true
            }

            if preparing { ProgressView("正在处理图片") }
            if !pendingUploads.isEmpty {
                ForEach(pendingUploads) { item in
                    HStack {
                        Image(decorative: UploadImageProcessor.preview(item.image, watermark: imageOptions.watermark), scale: 1)
                            .resizable().scaledToFit().frame(width: 76, height: 58)
                        Spacer()
                        Button("移除待上传图片", systemImage: "xmark.circle") {
                            pendingUploads.removeAll { $0.id == item.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(working || preparing)
                    }
                }
                let title = pendingUploads.count == 1 ? "上传图片" : "上传 \(pendingUploads.count) 张图片"
                Button(mutation == .upload ? "上传中…" : title) {
                    Task { await upload() }
                }
                .disabled(uploadBlocked)
            }
        } header: {
            HStack {
                Text("上传")
                Spacer()
                Button("上传选项") { showsOptions = true }.disabled(working)
            }
        } footer: {
            Text("上传的图片可通过公开链接访问。")
        }
    }

    private var uploadResults: some View {
        Section {
            Text(uploaded.count == 1 ? "图片已上传" : "已上传 \(uploaded.count) 张图片")
                .foregroundStyle(Color.seekGreen)
            HStack {
                copyMenu(uploaded)
                if uploaded.count == 1, let image = uploaded.first {
                    Spacer()
                    ShareLink("分享链接", item: image.url)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var historySection: some View {
        Section {
            if loading, images.isEmpty { ProgressView("正在读取图片") }
            if !loading, images.isEmpty, error == nil {
                ContentUnavailableView("暂无图片", systemImage: "photo.on.rectangle")
            }
            if let selectedIDs {
                HStack {
                    Button(selectedIDs.count == images.count ? "取消全选" : "全选") {
                        self.selectedIDs = selectedIDs.count == images.count ? [] : Set(images.map(\.id))
                    }
                    Spacer()
                    Menu("操作 \(selectedIDs.count)") {
                        copyChoices(selectedImages)
                        Button("删除", systemImage: "trash", role: .destructive) { confirmDelete(selectedImages) }
                            .disabled(busy)
                    }
                    .disabled(selectedIDs.isEmpty || working)
                }
                .buttonStyle(.borderless)
            }
            ForEach(images) { image in
                if let selectedIDs {
                    Button {
                        if selectedIDs.contains(image.id) { self.selectedIDs?.remove(image.id) }
                        else { self.selectedIDs?.insert(image.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIDs.contains(image.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color.seekGreen)
                                .accessibilityHidden(true)
                            imageDetails(image, selecting: true)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                    .accessibilityAddTraits(selectedIDs.contains(image.id) ? .isSelected : [])
                } else {
                    HStack(spacing: 12) {
                        imageDetails(image, selecting: false)
                        Menu {
                            copyChoices([image])
                            ShareLink(item: image.url)
                            Button("删除", systemImage: "trash", role: .destructive) { confirmDelete([image]) }.disabled(busy)
                        } label: {
                            Image(systemName: "ellipsis").padding(.vertical, 12)
                        }
                        .accessibilityLabel("图片操作")
                        .buttonStyle(.borderless)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("删除", role: .destructive) { confirmDelete([image]) }.disabled(busy)
                    }
                }
            }
        } header: {
            HStack {
                Text("已上传图片")
                Spacer()
                if !images.isEmpty {
                    Button(selectedIDs == nil ? "选择" : "完成选择") {
                        selectedIDs = selectedIDs == nil ? [] : nil
                    }
                    .disabled(working)
                }
            }
        }
    }

    private func imageDetails(_ image: HostedImage, selecting: Bool) -> some View {
        HStack(spacing: 12) {
            ForumImageView(url: image.url, alt: image.filename, size: .thumbnail)
                .frame(width: 76, height: 58).clipped()
                .allowsHitTesting(!selecting).accessibilityHidden(selecting)
            VStack(alignment: .leading, spacing: 4) {
                Text(image.filename).lineLimit(1)
                if let date = image.uploadedAt {
                    ForumDateText(value: date).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func copyMenu(_ images: [HostedImage]) -> some View {
        Menu("复制链接", systemImage: "doc.on.doc") { copyChoices(images) }
    }

    @ViewBuilder private func copyChoices(_ images: [HostedImage]) -> some View {
        ForEach(HostedImageLinkFormat.allCases, id: \.self) { format in
            Button("复制 \(format.title)") {
                copy(images, as: format)
                message = "链接已复制。"
            }
        }
    }

    private func copy(_ images: [HostedImage], as format: HostedImageLinkFormat) {
        guard !images.isEmpty else { return }
        UIPasteboard.general.string = images.map { format.text(for: $0.url) }.joined(separator: "\n")
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func initialize() async {
        guard !initialized else { return }
        initialized = true
        do {
            savedKey = try NodeImageKeyStore.read(userID: userID)
            key = savedKey
            images = account.nodeImageHistory.cachedImages(userID: userID, key: savedKey) ?? []
            await load()
        } catch { self.error = SiteError.displayMessage(for: error, service: "NodeImage") }
    }

    private func saveKey() async {
        let value = trimmedKey
        guard !busy, ownsLibrary, value != savedKey, NodeImageAPI.validKey(value) else { return }
        mutation = .saveKey
        error = nil
        message = nil
        defer { mutation = nil }
        do {
            let result = try await client.images(key: value)
            guard !Task.isCancelled, ownsLibrary else { return }
            try NodeImageKeyStore.save(value, userID: userID)
            savedKey = value
            key = value
            images = result
            account.nodeImageHistory.store(result, userID: userID, key: value)
            selectedIDs = nil
            uploaded = []
            message = "密钥已保存。"
        } catch {
            if !Task.isCancelled, ownsLibrary { self.error = SiteError.displayMessage(for: error, service: "NodeImage") }
        }
    }

    private func syncKey(regenerating: Bool) async {
        guard !busy, ownsLibrary else { return }
        mutation = regenerating ? .rotateKey : .syncKey
        error = nil
        message = nil
        do {
            let updated = try await account.syncNodeImageKey(userID: userID, regenerating: regenerating)
            mutation = nil
            guard !Task.isCancelled, ownsLibrary else { return }
            if updated != savedKey {
                account.nodeImageHistory.reset()
                images = []
                selectedIDs = nil
                uploaded = []
            }
            savedKey = updated
            key = updated
            message = regenerating ? "密钥已更新。" : "密钥已同步。"
            await load()
        } catch {
            mutation = nil
            if !Task.isCancelled, ownsLibrary { self.error = SiteError.displayMessage(for: error, service: "NodeImage") }
        }
    }

    private func removeKey() {
        guard !busy, ownsLibrary else { return }
        do {
            try NodeImageKeyStore.save("", userID: userID)
            account.nodeImageHistory.reset()
            key = ""
            savedKey = ""
            images = []
            pendingUploads = []
            uploaded = []
            selectedIDs = nil
            error = nil
            message = "本机密钥已移除。"
        } catch { self.error = SiteError.displayMessage(for: error, service: "NodeImage") }
    }

    private func load() async {
        guard !savedKey.isEmpty, !loading, !working, ownsLibrary else { return }
        loading = true
        error = nil
        defer {
            loading = false
            uploadedWhileLoading = []
        }
        do {
            let result = try await client.images(key: savedKey)
            guard !Task.isCancelled, ownsLibrary else { return }
            images = account.nodeImageHistory.finishRefresh(
                result, recentUploads: uploadedWhileLoading, userID: userID, key: savedKey
            )
            selectedIDs?.formIntersection(images.map(\.id))
        } catch {
            if !Task.isCancelled, ownsLibrary, !working, self.error == nil { self.error = SiteError.displayMessage(for: error, service: "NodeImage") }
        }
    }

    private func add(_ inputs: [NodeImageInput]) {
        guard !inputs.isEmpty, !savedKey.isEmpty, !preparing, !working, remainingSlots > 0, ownsLibrary else { return }
        let batch = inputs.prefix(remainingSlots)
        preparing = true
        error = nil
        message = nil
        Task {
            defer { preparing = false }
            var failures = 0
            var latestError: String?
            for input in batch {
                guard !Task.isCancelled, ownsLibrary else { return }
                do {
                    let image = try await input.prepare()
                    guard !Task.isCancelled, ownsLibrary else { return }
                    pendingUploads.append(PendingUpload(image: image))
                } catch {
                    failures += 1
                    latestError = SiteError.displayMessage(for: error, service: "NodeImage")
                }
            }
            guard ownsLibrary else { return }
            if failures > 0 {
                error = batch.count == 1 ? latestError : "\(failures) 张图片无法处理。\(latestError ?? "")"
            } else if batch.count < inputs.count {
                message = "一次最多准备 \(uploadLimit) 张图片。"
            }
        }
    }

    private func upload() async {
        guard !pendingUploads.isEmpty, !uploadBlocked, !savedKey.isEmpty, ownsLibrary else { return }
        mutation = .upload
        error = nil
        message = nil
        uploaded = []
        defer { mutation = nil }
        let expiration = preferences.deleteAfterDays
        let options = imageOptions
        for item in pendingUploads {
            guard !Task.isCancelled, ownsLibrary else { return }
            let payload: (data: Data, format: NodeImageAPI.ImageFormat)
            do {
                payload = try await Task.detached(priority: .userInitiated) {
                    try UploadImageProcessor.render(item.image, options: options)
                }.value
            } catch {
                if ownsLibrary { self.error = SiteError.displayMessage(for: error, service: "NodeImage") }
                break
            }
            guard !Task.isCancelled, ownsLibrary else { return }
            do {
                let result = try await client.upload(image: payload.data, format: payload.format, key: savedKey, deleteAfterDays: expiration)
                guard ownsLibrary else { return }
                pendingUploads.removeAll { $0.id == item.id }
                uploaded.append(result)
                if !result.id.isEmpty {
                    images.removeAll { $0.id == result.id }
                    images.insert(result, at: 0)
                    if loading {
                        uploadedWhileLoading.removeAll { $0.id == result.id }
                        uploadedWhileLoading.append(result)
                    }
                    account.nodeImageHistory.recordUpload(result, userID: userID, key: savedKey)
                }
            } catch {
                guard ownsLibrary else { return }
                self.error = SiteError.displayMessage(for: error, service: "NodeImage") + " 上传结果不确定时，请先刷新列表检查。"
                break
            }
        }
        if preferences.copyAfterUpload, !uploaded.isEmpty {
            copy(uploaded, as: preferences.linkFormat)
            message = "链接已复制。"
        }
    }

    private func confirmDelete(_ images: [HostedImage]) {
        guard !images.isEmpty, !busy else { return }
        pendingDeletion = images
        confirmsDelete = true
    }

    private func deletePendingImages() async {
        guard !pendingDeletion.isEmpty, !busy, ownsLibrary else { return }
        mutation = .delete
        error = nil
        message = nil
        defer {
            mutation = nil
            pendingDeletion = []
            if selectedIDs?.isEmpty == true { selectedIDs = nil }
        }
        var deleted = 0
        for image in pendingDeletion {
            guard !Task.isCancelled, ownsLibrary else { return }
            do {
                try await client.delete(image, key: savedKey)
                guard ownsLibrary else { return }
                images.removeAll { $0.id == image.id }
                uploaded.removeAll { $0.id == image.id }
                selectedIDs?.remove(image.id)
                updateCachedHistory()
                deleted += 1
            } catch {
                if ownsLibrary { self.error = SiteError.displayMessage(for: error, service: "NodeImage") }
                break
            }
        }
        if deleted > 0 { message = "已删除 \(deleted) 张图片。" }
    }

    private func updateCachedHistory() {
        let history = account.nodeImageHistory
        if history.cachedImages(userID: userID, key: savedKey) != nil {
            history.store(images, userID: userID, key: savedKey)
        }
    }
}
