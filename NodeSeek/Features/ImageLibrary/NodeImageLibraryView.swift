import NodeSeekClient
import NodeSeekCore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum NodeImageMetrics {
    static let cardPadding: CGFloat = 20
    /// Trims font line-height air above the disconnected card's title so top and bottom visual margins match.
    static let topGlyphTrim: CGFloat = 3
    static let cardSpacing: CGFloat = 16
    static let blockSpacing: CGFloat = 14
    static let textSpacing: CGFloat = 6

    static let optionsPillHeight: CGFloat = 32
    static let sourcePillHeight: CGFloat = 42
    static let sourceButtonSpacing: CGFloat = 8

    static let pendingTileSize: CGFloat = 88
    static let pendingTileRadius: CGFloat = 14
    static let pendingTileSpacing: CGFloat = 10
    static let pendingRemoveSize: CGFloat = 24
    static let pendingCornerInset: CGFloat = 6

    static let rowVerticalInset: CGFloat = 10
    static let rowHorizontalInset: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let rowLineSpacing: CGFloat = 4
    static let rowThumbnailWidth: CGFloat = 68
    static let rowThumbnailHeight: CGFloat = 52
    static let rowThumbnailRadius: CGFloat = 10
    static let rowActionSize: CGFloat = 34
    static let separatorInset: CGFloat = rowThumbnailWidth + rowSpacing

    static let gridSpacing: CGFloat = 8
    static let gridTileRadius: CGFloat = 12
    static let gridBadgeInset: CGFloat = 8

    static let connectCardInsets = EdgeInsets(
        top: cardPadding - topGlyphTrim,
        leading: cardPadding,
        bottom: cardPadding,
        trailing: cardPadding
    )

    static let uploadCardInsets = EdgeInsets(
        top: cardPadding,
        leading: cardPadding,
        bottom: cardPadding,
        trailing: cardPadding
    )

    static let historyRowInsets = EdgeInsets(
        top: rowVerticalInset,
        leading: rowHorizontalInset,
        bottom: rowVerticalInset,
        trailing: rowHorizontalInset
    )

    static let gridCardInsets = EdgeInsets(
        top: 14,
        leading: 14,
        bottom: 14,
        trailing: 14
    )
}

struct NodeImageLibraryView: View {
    let userID: Int

    @Environment(AccountSession.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var preferences: NodeImageUploadPreferences

    @State private var key = ""
    @State private var savedKey = ""
    @State private var initialized = false
    @State private var images: [HostedImage] = []
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var pendingUploads: [NodeImagePendingUpload] = []
    @State private var uploaded: [HostedImage] = []
    @State private var uploadedWhileLoading: [HostedImage] = []
    @State private var totalBatchCount = 0
    @State private var selectedIDs: Set<String>?
    @State private var pendingDeletion: [HostedImage] = []
    @State private var confirmsDelete = false
    @State private var confirmsKeyRotation = false
    @State private var importsFiles = false
    @State private var showsOptions = false
    @State private var showsKeySheet = false
    @State private var activeGallery: ImageGallery?
    @State private var loading = false
    @State private var preparing = false
    @State private var mutation: Mutation?
    @State private var error: String?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    private enum Mutation {
        case upload, delete, saveKey, syncKey, rotateKey
    }

    private let uploadLimit = 10
    private var remainingSlots: Int { max(0, uploadLimit - pendingUploads.count) }
    private var working: Bool { mutation != nil }
    private var busy: Bool { working || loading || preparing }
    private var uploadBlocked: Bool { working || preparing }
    private var client: NodeImageClient { account.nodeImageHistory.client }
    private var ownsLibrary: Bool { account.user?.id == userID }
    private var selectedImages: [HostedImage] { images.filter { selectedIDs?.contains($0.id) == true } }
    private var imageOptions: UploadImageOptions { preferences.imageOptions(username: account.user?.name) }
    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(userID: Int) {
        self.userID = userID
        preferences = NodeImageUploadPreferences(userID: userID)
    }

    var body: some View {
        List {
            if let error {
                errorSection(error)
            }
            if savedKey.isEmpty {
                disconnectedSections
            } else {
                connectedUploadSection
                historySection
            }
        }
        .seekGroupedList()
        .contentMargins(.top, 12, for: .scrollContent)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.24), value: savedKey.isEmpty)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.22), value: preferences.layoutMode)
        .navigationTitle("图片上传与管理")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(working)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedIDs != nil {
                    Button("完成") {
                        selectedIDs = nil
                    }
                    .fontWeight(.semibold)
                    .disabled(working)
                    .accessibilityIdentifier("nodeimage-done-selecting")
                } else {
                    Button {
                        key = ""
                        showsKeySheet = true
                    } label: {
                        Label("密钥管理", systemImage: "key")
                    }
                    .disabled(working)
                    .accessibilityIdentifier("nodeimage-key-button")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let selectedIDs, !images.isEmpty {
                NodeImageSelectionBar(
                    selectedCount: selectedIDs.count,
                    totalCount: images.count,
                    isBusy: busy,
                    isWorking: working,
                    onToggleAll: {
                        self.selectedIDs = selectedIDs.count == images.count ? [] : Set(images.map(\.id))
                    },
                    onCopy: { format in
                        copy(selectedImages, as: format)
                    },
                    onDelete: {
                        confirmDelete(selectedImages)
                    }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Button {
                    dismissToast()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.seekGreen)
                            .accessibilityHidden(true)
                        Text(toastMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.seekOnInk)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.seekInk, in: .capsule)
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.bottom, selectedIDs != nil ? 76 : 16)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("nodeimage-toast")
            }
        }
        .sheet(isPresented: $showsOptions) {
            NodeImageUploadOptionsView(
                compressImages: preferences.$compressImages,
                compressionQuality: preferences.$compressionQuality,
                addWatermark: preferences.$addWatermark,
                watermarkWebsite: preferences.$watermarkWebsite,
                watermarkUsername: preferences.$watermarkUsername,
                copyAfterUpload: preferences.$copyAfterUpload,
                linkFormat: preferences.$linkFormat,
                autoDelete: preferences.$autoDelete,
                deleteDays: preferences.$deleteDays,
                onReset: { preferences.resetToDefaults() }
            )
        }
        .sheet(isPresented: $showsKeySheet) {
            NodeImageKeySheet(
                savedKey: savedKey,
                draftKey: $key,
                isSyncing: mutation == .syncKey,
                isRotating: mutation == .rotateKey,
                isSaving: mutation == .saveKey,
                isBusy: busy,
                ownsLibrary: ownsLibrary,
                onSync: { Task { await syncKey(regenerating: false, dismissSheetOnSuccess: true) } },
                onRotate: { Task { await syncKey(regenerating: true, dismissSheetOnSuccess: true) } },
                onSaveKey: { Task { await saveKey() } },
                onRemoveKey: { removeKey() }
            )
        }
        .fullScreenCover(item: $activeGallery) { gallery in
            ImageViewer(gallery: gallery, initialImageIsThumbnail: true)
        }
        .fileImporter(isPresented: $importsFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): add(urls.map(NodeImageInput.file))
            case .failure(let error): self.error = SiteError.displayMessage(for: error)
            }
        }
        .task { await initialize() }
        .onDisappear { toastTask?.cancel() }
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
        .alert("更新 NodeImage 密钥？", isPresented: $confirmsKeyRotation) {
            Button("更新密钥", role: .destructive) { Task { await syncKey(regenerating: true, dismissSheetOnSuccess: false) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("更新后旧密钥会失效，使用旧密钥的工具也需要换成新密钥。")
        }
    }

    // MARK: - Sections

    private func errorSection(_ text: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Color.seekInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        error = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭错误提示")
                }

                if !savedKey.isEmpty {
                    Button("刷新已上传列表") {
                        Task { await load() }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .disabled(busy)
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(Color.seekCard)
            .accessibilityIdentifier("nodeimage-error-banner")
        }
    }

    @ViewBuilder
    private var disconnectedSections: some View {
        Section {
            NodeImageConnectCard(
                isSyncing: mutation == .syncKey,
                isDisabled: !ownsLibrary || (busy && mutation != .syncKey),
                onConnect: { Task { await syncKey(regenerating: false, dismissSheetOnSuccess: false) } }
            )
            .listRowInsets(NodeImageMetrics.connectCardInsets)
            .listRowBackground(Color.seekCard)
            .listRowSeparator(.hidden)
        }

        Section {
            Button {
                key = ""
                showsKeySheet = true
            } label: {
                SeekRowLabel(title: "手动设置密钥", symbol: "key")
            }
            .disabled(!ownsLibrary || busy)
            .listRowBackground(Color.seekCard)
            .accessibilityIdentifier("nodeimage-manual-key-row")

            Button {
                confirmsKeyRotation = true
            } label: {
                HStack(spacing: 12) {
                    SeekRowLabel(title: "更新密钥", symbol: "arrow.triangle.2.circlepath")
                    Spacer(minLength: 0)
                    if mutation == .rotateKey {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(!ownsLibrary || busy)
            .listRowBackground(Color.seekCard)
            .accessibilityIdentifier("nodeimage-rotate-key-row")
        } header: {
            SeekSectionTitle(title: "其他连接方式")
        }
    }

    private var connectedUploadSection: some View {
        Section {
            NodeImageUploadCard(
                pickedPhotos: $pickedPhotos,
                pendingUploads: pendingUploads,
                uploadLimit: uploadLimit,
                config: preferences.config,
                username: account.user?.name,
                watermarkText: imageOptions.watermark,
                isPreparing: preparing,
                isUploading: mutation == .upload,
                uploadedInBatchCount: uploaded.count,
                totalBatchCount: totalBatchCount,
                ownsLibrary: ownsLibrary,
                onOpenFiles: { importsFiles = true },
                onPaste: pasteFromClipboard,
                onDropProviders: { providers in
                    guard !working, !preparing, remainingSlots > 0, ownsLibrary else { return false }
                    add(providers.map(NodeImageInput.provider))
                    return true
                },
                onOpenOptions: { showsOptions = true },
                onRemovePending: { id in pendingUploads.removeAll { $0.id == id } },
                onClearPending: { pendingUploads.removeAll() },
                onUpload: { Task { await upload() } }
            )
            .listRowInsets(NodeImageMetrics.uploadCardInsets)
            .listRowBackground(Color.seekCard)

            if !uploaded.isEmpty && mutation != .upload {
                NodeImageUploadResultRow(
                    uploaded: uploaded,
                    preferredFormat: preferences.linkFormat,
                    onCopy: { format in copy(uploaded, as: format) },
                    onDismiss: { uploaded = [] }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .listRowBackground(Color.seekCard)
            }
        }
    }

    private var historySection: some View {
        Section {
            if loading, images.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取已上传图片…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.seekCard)
                .listRowSeparator(.hidden)
            } else if !loading, images.isEmpty, error == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("暂无已上传图片")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.seekInk)
                    Text("从上方选择相册、文件或粘贴图片即可上传。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.seekCard)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("nodeimage-empty-history")
            } else if preferences.layoutMode == .grid {
                NodeImageHistoryGrid(
                    images: images,
                    preferredFormat: preferences.linkFormat,
                    selectedIDs: selectedIDs,
                    isBusy: busy,
                    isWorking: working,
                    onToggleSelect: toggleSelection,
                    onPreview: openGallery,
                    onCopy: copy,
                    onDelete: { confirmDelete([$0]) }
                )
                .listRowInsets(NodeImageMetrics.gridCardInsets)
                .listRowBackground(Color.seekCard)
                .listRowSeparator(.hidden)
            } else {
                ForEach(images) { image in
                    NodeImageHistoryRow(
                        image: image,
                        preferredFormat: preferences.linkFormat,
                        isSelecting: selectedIDs != nil,
                        isSelected: selectedIDs?.contains(image.id) == true,
                        isBusy: busy,
                        isWorking: working,
                        onToggleSelect: { toggleSelection(image) },
                        onPreview: { openGallery(for: image, thumbnail: $0) },
                        onCopy: { copy([image], as: $0) },
                        onDelete: { confirmDelete([image]) }
                    )
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + NodeImageMetrics.separatorInset }
                    .listRowInsets(NodeImageMetrics.historyRowInsets)
                    .listRowBackground(Color.seekCard)
                    .swipeActions(edge: .leading, allowsFullSwipe: selectedIDs == nil) {
                        if selectedIDs == nil {
                            Button {
                                copy([image], as: preferences.linkFormat)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                            .tint(Color.seekInk)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if selectedIDs == nil {
                            Button("删除", role: .destructive) {
                                confirmDelete([image])
                            }
                            .disabled(busy)
                        }
                    }
                }
            }
        } header: {
            historyHeader
        }
    }

    private var historyHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            SeekSectionTitle(
                title: "已上传图片",
                detail: images.isEmpty ? nil : "\(images.count) 张"
            )
            if !images.isEmpty {
                Button {
                    preferences.layoutMode = preferences.layoutMode == .list ? .grid : .list
                } label: {
                    Image(systemName: preferences.layoutMode == .list ? "square.grid.2x2" : "list.bullet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.seekInk)
                        .frame(width: 30, height: 30)
                        .background(Color.seekTray, in: .circle)
                }
                .buttonStyle(.seekRow)
                .accessibilityLabel(preferences.layoutMode == .list ? "切换为网格视图" : "切换为列表视图")
                .accessibilityIdentifier("nodeimage-layout-toggle")

                Button(selectedIDs == nil ? "选择" : "完成选择") {
                    selectedIDs = selectedIDs == nil ? [] : nil
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.seekInk)
                .buttonStyle(.seekRow)
                .disabled(working)
                .fixedSize()
                .accessibilityIdentifier("nodeimage-select-toggle")
            }
        }
        .textCase(nil)
    }

    // MARK: - Actions

    private func toggleSelection(_ image: HostedImage) {
        guard selectedIDs != nil else { return }
        if selectedIDs?.contains(image.id) == true {
            selectedIDs?.remove(image.id)
        } else {
            selectedIDs?.insert(image.id)
        }
    }

    private func openGallery(for target: HostedImage, thumbnail: CGImage?) {
        guard let startIndex = images.firstIndex(where: { $0.id == target.id }) else { return }
        let items = images.map { ImageGallery.Item(url: $0.url, alt: $0.filename) }
        if let thumbnail {
            activeGallery = ImageGallery(items: items, startIndex: startIndex, initialImage: thumbnail)
            return
        }
        Task {
            do {
                let loaded = try await ForumImageLoader.shared.load(target.url, size: .thumbnail, prioritized: true)
                guard !Task.isCancelled else { return }
                let latestItems = images.map { ImageGallery.Item(url: $0.url, alt: $0.filename) }
                let latestIndex = images.firstIndex(where: { $0.id == target.id }) ?? 0
                activeGallery = ImageGallery(items: latestItems, startIndex: latestIndex, initialImage: loaded)
            } catch {
                if !Task.isCancelled {
                    self.error = SiteError.displayMessage(for: error, service: "NodeImage")
                }
            }
        }
    }

    private func pasteFromClipboard() {
        guard !working, !preparing, remainingSlots > 0, ownsLibrary else { return }
        let providers = UIPasteboard.general.itemProviders.filter { provider in
            provider.registeredContentTypes.contains { $0.conforms(to: .image) }
        }
        guard !providers.isEmpty else {
            showToast("剪贴板中没有可粘贴的图片")
            return
        }
        add(providers.map(NodeImageInput.provider))
    }

    private func copy(_ list: [HostedImage], as format: HostedImageLinkFormat) {
        guard !list.isEmpty else { return }
        UIPasteboard.general.string = list.map { format.text(for: $0.url) }.joined(separator: "\n")
        showToast(list.count == 1 ? "已复制 \(format.title) 链接" : "已复制 \(list.count) 条 \(format.title) 链接")
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .snappy(duration: 0.22)) {
            toastMessage = text
        }
        toastTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(2200))
                guard !Task.isCancelled else { return }
                dismissToast()
            } catch {}
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .snappy(duration: 0.2)) {
            toastMessage = nil
        }
    }

    private func initialize() async {
        guard !initialized else { return }
        initialized = true
        do {
            savedKey = try NodeImageKeyStore.read(userID: userID)
            key = ""
            images = account.nodeImageHistory.cachedImages(userID: userID, key: savedKey) ?? []
            await load()
        } catch {
            self.error = SiteError.displayMessage(for: error, service: "NodeImage")
        }
    }

    private func saveKey() async {
        let value = trimmedKey
        guard !busy, ownsLibrary, value != savedKey, NodeImageAPI.validKey(value) else { return }
        mutation = .saveKey
        error = nil
        defer { mutation = nil }
        do {
            let result = try await client.images(key: value)
            guard !Task.isCancelled, ownsLibrary else { return }
            try NodeImageKeyStore.save(value, userID: userID)
            savedKey = value
            key = ""
            images = result
            account.nodeImageHistory.store(result, userID: userID, key: value)
            selectedIDs = nil
            uploaded = []
            showsKeySheet = false
            showToast("密钥已保存")
        } catch {
            if !Task.isCancelled, ownsLibrary {
                self.error = SiteError.displayMessage(for: error, service: "NodeImage")
            }
        }
    }

    private func syncKey(regenerating: Bool, dismissSheetOnSuccess: Bool) async {
        guard !busy, ownsLibrary else { return }
        mutation = regenerating ? .rotateKey : .syncKey
        error = nil
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
            key = ""
            if dismissSheetOnSuccess {
                showsKeySheet = false
            }
            showToast(regenerating ? "密钥已更新" : "已连接并同步密钥")
            await load()
        } catch {
            mutation = nil
            if !Task.isCancelled, ownsLibrary {
                self.error = SiteError.displayMessage(for: error, service: "NodeImage")
            }
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
            showToast("本机密钥已移除")
        } catch {
            self.error = SiteError.displayMessage(for: error, service: "NodeImage")
        }
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
            if selectedIDs?.isEmpty == true, images.isEmpty {
                selectedIDs = nil
            }
        } catch {
            if !Task.isCancelled, ownsLibrary, !working, self.error == nil {
                self.error = SiteError.displayMessage(for: error, service: "NodeImage")
            }
        }
    }

    private func add(_ inputs: [NodeImageInput]) {
        guard !inputs.isEmpty, !savedKey.isEmpty, !preparing, !working, remainingSlots > 0, ownsLibrary else { return }
        let batch = inputs.prefix(remainingSlots)
        preparing = true
        error = nil
        Task {
            defer { preparing = false }
            var failures = 0
            var latestError: String?
            for input in batch {
                guard !Task.isCancelled, ownsLibrary else { return }
                do {
                    let image = try await input.prepare()
                    guard !Task.isCancelled, ownsLibrary else { return }
                    pendingUploads.append(NodeImagePendingUpload(image: image))
                } catch {
                    failures += 1
                    latestError = SiteError.displayMessage(for: error, service: "NodeImage")
                }
            }
            guard ownsLibrary else { return }
            if failures > 0 {
                error = batch.count == 1 ? latestError : "\(failures) 张图片无法处理。\(latestError ?? "")"
            } else if batch.count < inputs.count {
                showToast("一次最多准备 \(uploadLimit) 张图片")
            }
        }
    }

    private func upload() async {
        guard !pendingUploads.isEmpty, !uploadBlocked, !savedKey.isEmpty, ownsLibrary else { return }
        mutation = .upload
        error = nil
        uploaded = []
        totalBatchCount = pendingUploads.count
        defer {
            mutation = nil
            totalBatchCount = 0
        }
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
                let result = try await client.upload(
                    image: payload.data, format: payload.format, key: savedKey, deleteAfterDays: expiration
                )
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
        }
    }

    private func confirmDelete(_ target: [HostedImage]) {
        guard !target.isEmpty, !busy else { return }
        pendingDeletion = target
        confirmsDelete = true
    }

    private func deletePendingImages() async {
        guard !pendingDeletion.isEmpty, !busy, ownsLibrary else { return }
        mutation = .delete
        error = nil
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
        if deleted > 0 {
            showToast("已删除 \(deleted) 张图片")
        }
    }

    private func updateCachedHistory() {
        let history = account.nodeImageHistory
        if history.cachedImages(userID: userID, key: savedKey) != nil {
            history.store(images, userID: userID, key: savedKey)
        }
    }
}
