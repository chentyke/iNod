import NodeSeekClient
import NodeSeekCore
import SwiftUI

struct NodeImageThumbnail: View {
    let url: URL
    let cornerRadius: CGFloat
    var onLoaded: ((CGImage) -> Void)? = nil

    @State private var image: CGImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Color.seekTray
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.seekHairline.opacity(0.6), lineWidth: 0.5)
            }
            .task(id: "\(url.absoluteString)#\(attempt)") {
                guard image == nil else { return }
                failed = false
                do {
                    let loaded = try await ForumImageLoader.shared.load(url, size: .thumbnail, prioritized: true)
                    try Task.checkCancellation()
                    image = loaded
                    onLoaded?(loaded)
                } catch {
                    if !Task.isCancelled { failed = true }
                }
            }
    }

    func retryIfFailed() -> Bool {
        guard failed else { return false }
        attempt += 1
        return true
    }
}

struct NodeImageHistoryRow: View {
    let image: HostedImage
    let preferredFormat: HostedImageLinkFormat
    let isSelecting: Bool
    let isSelected: Bool
    let isBusy: Bool
    let isWorking: Bool
    let onToggleSelect: () -> Void
    let onPreview: (CGImage?) -> Void
    let onCopy: (HostedImageLinkFormat) -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var loadedThumbnail: CGImage?
    @State private var retryTrigger = 0

    var body: some View {
        Group {
            if isSelecting {
                Button(action: onToggleSelect) {
                    HStack(spacing: NodeImageMetrics.rowSpacing) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.seekGreen : Color(uiColor: .tertiaryLabel))
                            .accessibilityHidden(true)
                        rowMainContent
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .accessibilityIdentifier("nodeimage-select-\(image.id)")
                .accessibilityLabel(image.filename)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                HStack(spacing: NodeImageMetrics.rowSpacing) {
                    Button {
                        onPreview(loadedThumbnail)
                    } label: {
                        rowMainContent
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("nodeimage-preview-\(image.id)")
                    .accessibilityLabel(image.filename)
                    .accessibilityHint("打开全屏图片预览")

                    actionMenu
                }
                .contextMenu {
                    menuItems
                }
            }
        }
    }

    private var rowMainContent: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: NodeImageMetrics.rowSpacing))

        return layout {
            NodeImageThumbnail(
                url: image.url,
                cornerRadius: NodeImageMetrics.rowThumbnailRadius
            ) { cgImage in
                loadedThumbnail = cgImage
            }
            .id(retryTrigger)
            .frame(width: NodeImageMetrics.rowThumbnailWidth, height: NodeImageMetrics.rowThumbnailHeight)

            VStack(alignment: .leading, spacing: NodeImageMetrics.rowLineSpacing) {
                Text(image.filename)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.seekInk)
                    .lineLimit(1)
                    .truncationMode(.middle)

                metadataRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var metadataRow: some View {
        let badge = image.formatBadge
        if image.uploadedAt != nil || badge != nil {
            HStack(spacing: 6) {
                if let date = image.uploadedAt {
                    ForumDateText(value: date)
                }
                if image.uploadedAt != nil, badge != nil {
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if let badge {
                    Text(badge)
                }
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var actionMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: NodeImageMetrics.rowActionSize, height: NodeImageMetrics.rowActionSize)
                .background(Color.seekTray, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("图片操作")
        .accessibilityIdentifier("nodeimage-more-\(image.id)")
    }

    @ViewBuilder
    private var menuItems: some View {
        Section {
            Button("复制 \(preferredFormat.title)", systemImage: "doc.on.doc") {
                onCopy(preferredFormat)
            }
            ForEach(HostedImageLinkFormat.allCases.filter { $0 != preferredFormat }, id: \.self) { format in
                Button("复制 \(format.title)") {
                    onCopy(format)
                }
            }
        }
        Section {
            Button("预览大图", systemImage: "arrow.up.left.and.arrow.down.right") {
                onPreview(loadedThumbnail)
            }
            ShareLink("分享链接", item: image.url)
        }
        Section {
            Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                .disabled(isBusy)
        }
    }
}

struct NodeImageHistoryGrid: View {
    let images: [HostedImage]
    let preferredFormat: HostedImageLinkFormat
    let selectedIDs: Set<String>?
    let isBusy: Bool
    let isWorking: Bool
    let onToggleSelect: (HostedImage) -> Void
    let onPreview: (HostedImage, CGImage?) -> Void
    let onCopy: ([HostedImage], HostedImageLinkFormat) -> Void
    let onDelete: (HostedImage) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var containerWidth: CGFloat = 360

    private var columnCount: Int {
        if typeSize.isAccessibilitySize { return 2 }
        return containerWidth >= 520 ? 4 : 3
    }

    var body: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: NodeImageMetrics.gridSpacing),
            count: columnCount
        )
        LazyVGrid(columns: columns, spacing: NodeImageMetrics.gridSpacing) {
            ForEach(images) { image in
                NodeImageGridTile(
                    image: image,
                    preferredFormat: preferredFormat,
                    isSelecting: selectedIDs != nil,
                    isSelected: selectedIDs?.contains(image.id) == true,
                    isBusy: isBusy,
                    isWorking: isWorking,
                    onToggleSelect: { onToggleSelect(image) },
                    onPreview: { onPreview(image, $0) },
                    onCopy: { onCopy([image], $0) },
                    onDelete: { onDelete(image) }
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .accessibilityIdentifier("nodeimage-history-grid")
    }
}

private struct NodeImageGridTile: View {
    let image: HostedImage
    let preferredFormat: HostedImageLinkFormat
    let isSelecting: Bool
    let isSelected: Bool
    let isBusy: Bool
    let isWorking: Bool
    let onToggleSelect: () -> Void
    let onPreview: (CGImage?) -> Void
    let onCopy: (HostedImageLinkFormat) -> Void
    let onDelete: () -> Void

    @State private var loadedThumbnail: CGImage?

    var body: some View {
        Button {
            if isSelecting {
                onToggleSelect()
            } else {
                onPreview(loadedThumbnail)
            }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    NodeImageThumbnail(
                        url: image.url,
                        cornerRadius: NodeImageMetrics.gridTileRadius
                    ) { cgImage in
                        loadedThumbnail = cgImage
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.seekGreen : Color.white.opacity(0.92))
                            .background {
                                Circle()
                                    .fill(isSelected ? Color.seekCard : Color.black.opacity(0.32))
                                    .padding(2)
                            }
                            .padding(.top, NodeImageMetrics.gridBadgeInset)
                            .padding(.trailing, NodeImageMetrics.gridBadgeInset)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect(cornerRadius: NodeImageMetrics.gridTileRadius))
        }
        .buttonStyle(.seekRow)
        .disabled(isSelecting && isWorking)
        .accessibilityIdentifier(isSelecting ? "nodeimage-grid-select-\(image.id)" : "nodeimage-grid-tile-\(image.id)")
        .accessibilityLabel(image.filename)
        .accessibilityAddTraits(isSelecting && isSelected ? .isSelected : [])
        .contextMenu {
            if !isSelecting {
                Section {
                    Button("复制 \(preferredFormat.title)", systemImage: "doc.on.doc") {
                        onCopy(preferredFormat)
                    }
                    ForEach(HostedImageLinkFormat.allCases.filter { $0 != preferredFormat }, id: \.self) { format in
                        Button("复制 \(format.title)") {
                            onCopy(format)
                        }
                    }
                }
                Section {
                    Button("预览大图", systemImage: "arrow.up.left.and.arrow.down.right") {
                        onPreview(loadedThumbnail)
                    }
                    ShareLink("分享链接", item: image.url)
                }
                Section {
                    Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                        .disabled(isBusy)
                }
            }
        }
    }
}

struct NodeImageSelectionBar: View {
    let selectedCount: Int
    let totalCount: Int
    let isBusy: Bool
    let isWorking: Bool
    let onToggleAll: () -> Void
    let onCopy: (HostedImageLinkFormat) -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var allSelected: Bool {
        totalCount > 0 && selectedCount == totalCount
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            HStack(spacing: 10) {
                Button(allSelected ? "取消全选" : "全选", action: onToggleAll)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.seekInk)
                    .buttonStyle(.seekRow)
                    .disabled(isWorking)
                    .accessibilityIdentifier("nodeimage-select-all")

                Text("已选 \(selectedCount) 张")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(HostedImageLinkFormat.allCases, id: \.self) { format in
                        Button("复制 \(format.title)") {
                            onCopy(format)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                        Text("复制链接")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(selectedCount == 0 || isWorking ? Color.secondary : Color.seekOnInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(selectedCount == 0 || isWorking ? Color.seekTray : Color.seekInk, in: .capsule)
                }
                .disabled(selectedCount == 0 || isWorking)
                .accessibilityIdentifier("nodeimage-batch-copy")

                Button(role: .destructive, action: onDelete) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                        Text("删除")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(selectedCount == 0 || isBusy ? Color.secondary : Color.red)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(Color.seekTray, in: .capsule)
                }
                .buttonStyle(.seekRow)
                .disabled(selectedCount == 0 || isBusy)
                .accessibilityIdentifier("nodeimage-batch-delete")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.seekCard, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.seekHairline.opacity(0.75), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, SeekLayout.gutter)
        .padding(.bottom, 8)
        .readableColumn()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nodeimage-selection-bar")
    }
}
