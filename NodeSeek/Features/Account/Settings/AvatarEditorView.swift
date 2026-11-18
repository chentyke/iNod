import NodeSeekClient
import PhotosUI
import SwiftUI

struct AvatarEditorView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var item: PhotosPickerItem?
    @State private var avatar: PreparedAvatar?
    @State private var preparing = false
    @State private var busy = false
    @State private var error: String?
    @State private var success = false

    private var isWorking: Bool {
        preparing || busy
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: AccountSettingsMetrics.blockSpacing) {
                    VStack(spacing: 12) {
                        Group {
                            if let avatar {
                                Image(decorative: avatar.image, scale: 1)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(
                                        width: AccountSettingsMetrics.editorAvatarSize,
                                        height: AccountSettingsMetrics.editorAvatarSize
                                    )
                                    .clipShape(.circle)
                            } else {
                                AvatarView(
                                    name: account.user?.name ?? "",
                                    url: account.user?.avatarURL,
                                    size: AccountSettingsMetrics.editorAvatarSize
                                )
                            }
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(Color.seekHairline.opacity(0.5), lineWidth: 0.5)
                        }

                        SettingsStatusPill(
                            text: avatar == nil ? "当前头像" : "待保存预览",
                            active: avatar != nil
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("avatar-editor-preview")

                    Text("自动取照片中央正方形区域并缩放为标准头像尺寸。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: AccountSettingsMetrics.buttonSpacing) {
                        if avatar != nil {
                            SettingsActionPill(
                                title: "保存头像",
                                symbol: "checkmark",
                                busyTitle: "正在上传…",
                                isBusy: busy
                            ) {
                                Task { await upload() }
                            }
                            .accessibilityIdentifier("avatar-save-button")
                        }

                        let hasAvatar = avatar != nil
                        PhotosPicker(selection: $item, matching: .images) {
                            ZStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo.on.rectangle")
                                        .accessibilityHidden(true)
                                    Text(hasAvatar ? "重新选择照片" : "选择照片")
                                        .lineLimit(1)
                                }
                                .opacity(preparing ? 0 : 1)

                                if preparing {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(hasAvatar ? Color.seekInk : Color.seekOnInk)
                                        Text("正在处理照片…")
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .clipShape(.rect)
                        }
                        .buttonStyle(.seekPill(primary: !hasAvatar, surface: .seekTray))
                        .disabled(isWorking)
                        .accessibilityIdentifier("avatar-pick-button")

                        if avatar != nil && !busy {
                            Button("撤销选择") {
                                avatar = nil
                                item = nil
                                error = nil
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.seekRow)
                            .padding(.top, 2)
                            .accessibilityIdentifier("avatar-reset-button")
                        }
                    }
                }
                .listRowInsets(AccountSettingsMetrics.shapeCardInsets)
                .listRowBackground(Color.seekCard)
                .listRowSeparator(.hidden)
            }

            if let error {
                Section {
                    SettingsFeedbackRow(message: error, isSuccess: false)
                        .listRowBackground(Color.seekCard)
                }
            } else if success {
                Section {
                    SettingsFeedbackRow(message: "头像已更新并同步到 NodeSeek。", isSuccess: true)
                        .listRowBackground(Color.seekCard)
                }
            }
        }
        .seekGroupedList()
        .contentMargins(.top, 12, for: .scrollContent)
        .navigationTitle("修改头像")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .interactiveDismissDisabled(busy)
        .task(id: item) {
            guard let item else { return }
            error = nil
            success = false
            preparing = true
            defer { preparing = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw SiteError.invalidResponse
                }
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try AvatarProcessor.prepare(data)
                }.value
                try Task.checkCancellation()
                avatar = prepared
            } catch {
                if !Task.isCancelled {
                    self.error = SiteError.displayMessage(for: error)
                }
            }
        }
    }

    private func upload() async {
        guard !busy, let avatar else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await account.website.uploadAvatar(avatar.png, userID: userID)
            self.avatar = nil
            item = nil
            success = true
            account.avatarDidChange()
            await account.refresh(force: true)
        } catch {
            self.error = SiteError.displayMessage(for: error)
        }
    }
}
