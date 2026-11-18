import NodeSeekClient
import NodeSeekCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct NodeImagePendingUpload: Identifiable {
    let id = UUID()
    let image: PreparedUploadImage
}

struct NodeImageUploadCard: View {
    @Binding var pickedPhotos: [PhotosPickerItem]
    let pendingUploads: [NodeImagePendingUpload]
    let uploadLimit: Int
    let config: NodeImageUploadConfig
    let username: String?
    let watermarkText: String
    let isPreparing: Bool
    let isUploading: Bool
    let uploadedInBatchCount: Int
    let totalBatchCount: Int
    let ownsLibrary: Bool
    let onOpenFiles: () -> Void
    let onPaste: () -> Void
    let onDropProviders: ([NSItemProvider]) -> Bool
    let onOpenOptions: () -> Void
    let onRemovePending: (UUID) -> Void
    let onClearPending: () -> Void
    let onUpload: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var remainingSlots: Int {
        max(0, uploadLimit - pendingUploads.count)
    }

    private var sourcesDisabled: Bool {
        !ownsLibrary || isUploading || isPreparing || remainingSlots == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NodeImageMetrics.blockSpacing) {
            headerRow
            optionsSummaryButton
            sourceButtons

            if isPreparing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在处理所选图片…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !pendingUploads.isEmpty {
                pendingStrip
                uploadActionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [.image], isTargeted: nil, perform: onDropProviders)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nodeimage-upload-card")
    }

    private var headerRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("上传图片")
                    .font(.headline)
                    .foregroundStyle(Color.seekInk)
                if !pendingUploads.isEmpty {
                    Text("\(pendingUploads.count) / \(uploadLimit)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            Button(action: onOpenOptions) {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                    Text("上传选项")
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.seekInk)
                .padding(.horizontal, 12)
                .frame(minHeight: NodeImageMetrics.optionsPillHeight)
                .background(Color.seekTray, in: .capsule)
            }
            .buttonStyle(.seekRow)
            .disabled(isUploading)
            .accessibilityIdentifier("nodeimage-options-button")
        }
    }

    private var optionsSummaryButton: some View {
        let active = config.hasActiveProcessing(username: username)
        let summary = config.summaryItems(username: username).joined(separator: " · ")
        return Button(action: onOpenOptions) {
            HStack(spacing: 6) {
                if active {
                    Circle()
                        .fill(Color.seekGreen)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text("\(summary) · 公开链接")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
        .accessibilityIdentifier("nodeimage-options-summary")
        .accessibilityLabel("当前上传设置：\(summary)，公开链接")
        .accessibilityHint("点按调整上传选项")
    }

    @ViewBuilder
    private var sourceButtons: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: NodeImageMetrics.sourceButtonSpacing))
            : AnyLayout(HStackLayout(spacing: NodeImageMetrics.sourceButtonSpacing))

        layout {
            PhotosPicker(
                selection: $pickedPhotos,
                maxSelectionCount: max(1, remainingSlots),
                selectionBehavior: .ordered,
                matching: .images
            ) {
                NodeImageSourcePillLabel(title: "相册", symbol: "photo.on.rectangle", isDisabled: sourcesDisabled)
            }
            .buttonStyle(.seekRow)
            .disabled(sourcesDisabled)
            .accessibilityLabel("选择图片")
            .accessibilityIdentifier("nodeimage-pick-photos")

            Button(action: onOpenFiles) {
                NodeImageSourcePillLabel(title: "文件", symbol: "folder", isDisabled: sourcesDisabled)
            }
            .buttonStyle(.seekRow)
            .disabled(sourcesDisabled)
            .accessibilityLabel("从文件选择图片")
            .accessibilityIdentifier("nodeimage-pick-files")

            Button(action: onPaste) {
                NodeImageSourcePillLabel(title: "粘贴", symbol: "doc.on.clipboard", isDisabled: sourcesDisabled)
            }
            .buttonStyle(.seekRow)
            .disabled(sourcesDisabled)
            .accessibilityLabel("粘贴图片")
            .accessibilityIdentifier("nodeimage-paste-button")
        }
    }

    private var pendingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NodeImageMetrics.pendingTileSpacing) {
                ForEach(Array(pendingUploads.enumerated()), id: \.element.id) { index, item in
                    pendingTile(item, index: index)
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .accessibilityIdentifier("nodeimage-pending-strip")
    }

    private func pendingTile(_ item: NodeImagePendingUpload, index: Int) -> some View {
        let preview = UploadImageProcessor.preview(item.image, watermark: watermarkText)
        let size = NodeImageMetrics.pendingTileSize
        let radius = NodeImageMetrics.pendingTileRadius
        let inset = NodeImageMetrics.pendingCornerInset
        return Image(decorative: preview, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(Color.seekTray)
            .clipShape(.rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.seekHairline.opacity(0.6), lineWidth: 0.5)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    onRemovePending(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.seekOnInk)
                        .frame(width: NodeImageMetrics.pendingRemoveSize, height: NodeImageMetrics.pendingRemoveSize)
                        .background(Color.seekInk.opacity(0.76), in: .circle)
                        .padding(.top, inset)
                        .padding(.trailing, inset)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isUploading || isPreparing)
                .accessibilityLabel("移除第 \(index + 1) 张待上传图片")
            }
    }

    private var uploadActionRow: some View {
        let uploadTitle = pendingUploads.count == 1
            ? "上传图片"
            : "上传 \(pendingUploads.count) 张图片"
        let progressText = totalBatchCount > 1
            ? "正在上传 \(min(totalBatchCount, uploadedInBatchCount + 1)) / \(totalBatchCount)…"
            : "正在上传…"
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))

        return layout {
            Button(action: onUpload) {
                ZStack {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle")
                            .accessibilityHidden(true)
                        Text(uploadTitle)
                            .lineLimit(1)
                    }
                    .opacity(isUploading ? 0 : 1)

                    if isUploading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.seekOnInk)
                            Text(progressText)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
                .clipShape(.rect)
            }
            .buttonStyle(.seekPill)
            .allowsHitTesting(!isUploading && !isPreparing)
            .disabled(isUploading || isPreparing)
            .accessibilityIdentifier("nodeimage-upload-submit")

            if pendingUploads.count > 1 && !isUploading {
                Button("清空", action: onClearPending)
                    .buttonStyle(.seekPill(primary: false, fullWidth: typeSize.isAccessibilitySize, surface: .seekTray))
                    .disabled(isPreparing)
                    .accessibilityLabel("清空待上传图片")
                    .accessibilityIdentifier("nodeimage-clear-pending")
            }
        }
    }
}

private struct NodeImageSourcePillLabel: View {
    let title: String
    let symbol: String
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.medium))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isDisabled ? Color.secondary : Color.seekInk)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: NodeImageMetrics.sourcePillHeight)
        .background(Color.seekTray, in: .capsule)
        .overlay {
            Capsule().strokeBorder(Color.seekHairline.opacity(0.55), lineWidth: 0.5)
        }
        .contentShape(.capsule)
    }
}

struct NodeImageUploadResultRow: View {
    let uploaded: [HostedImage]
    let preferredFormat: HostedImageLinkFormat
    let onCopy: (HostedImageLinkFormat) -> Void
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))

        layout {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.seekGreen)
                    .accessibilityHidden(true)
                Text(uploaded.count == 1 ? "图片已上传" : "已上传 \(uploaded.count) 张图片")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.seekInk)
            }

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Button {
                    onCopy(preferredFormat)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text("复制\(preferredFormat.title)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.seekInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.seekTray, in: .capsule)
                }
                .buttonStyle(.seekRow)
                .accessibilityIdentifier("nodeimage-copy-uploaded-default")

                Menu {
                    ForEach(HostedImageLinkFormat.allCases, id: \.self) { format in
                        Button("复制 \(format.title)") {
                            onCopy(format)
                        }
                    }
                    if uploaded.count == 1, let first = uploaded.first {
                        Divider()
                        ShareLink("分享链接", item: first.url)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.seekTray, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多复制格式与分享")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭上传结果提示")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nodeimage-upload-results")
    }
}
