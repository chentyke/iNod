import NodeSeekCore
import SwiftUI

struct NodeImageConnectCard: View {
    let isSyncing: Bool
    let isDisabled: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NodeImageMetrics.cardSpacing) {
            VStack(alignment: .leading, spacing: NodeImageMetrics.textSpacing) {
                Text("连接官方图床")
                    .font(.title3.bold())
                    .foregroundStyle(Color.seekInk)
                Text("使用当前论坛账号授权连接 NodeImage，即可上传与管理图片，并在发帖和回复时直接选图插入。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onConnect) {
                ZStack {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .accessibilityHidden(true)
                        Text("连接 NodeImage")
                            .lineLimit(1)
                    }
                    .opacity(isSyncing ? 0 : 1)

                    if isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.seekOnInk)
                            Text("正在连接…")
                                .lineLimit(1)
                        }
                    }
                }
                .clipShape(.rect)
            }
            .buttonStyle(.seekPill)
            .allowsHitTesting(!isSyncing)
            .disabled(isDisabled)
            .accessibilityIdentifier("nodeimage-connect-button")
            .accessibilityLabel(isSyncing ? "正在连接 NodeImage" : "连接 NodeImage")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nodeimage-connect-card")
    }
}

struct NodeImageKeySheet: View {
    let savedKey: String
    @Binding var draftKey: String
    let isSyncing: Bool
    let isRotating: Bool
    let isSaving: Bool
    let isBusy: Bool
    let ownsLibrary: Bool
    let onSync: () -> Void
    let onRotate: () -> Void
    let onSaveKey: () -> Void
    let onRemoveKey: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var revealsKey = false
    @State private var confirmsRotate = false
    @State private var confirmsRemove = false

    private var trimmedDraft: String {
        draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationError: String? {
        guard !trimmedDraft.isEmpty else { return nil }
        if trimmedDraft == savedKey { return nil }
        return NodeImageAPI.validKey(trimmedDraft) ? nil : "密钥需为 32 至 128 位十六进制字符。"
    }

    private var canSaveDraft: Bool {
        ownsLibrary && !isBusy && !trimmedDraft.isEmpty && trimmedDraft != savedKey && NodeImageAPI.validKey(trimmedDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("连接状态") {
                    HStack(spacing: NodeImageMetrics.rowSpacing) {
                        SeekIconTile(
                            symbol: savedKey.isEmpty ? "key" : "checkmark.shield",
                            tint: savedKey.isEmpty ? .seekInk : .seekGreen
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(savedKey.isEmpty ? "尚未保存密钥" : "已连接 NodeImage")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.seekInk)
                            if savedKey.isEmpty {
                                Text("可通过论坛账号一键同步，或手动粘贴密钥")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("本机密钥 \(NodeImageAPI.maskedKey(savedKey))")
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.secondary)
                                    .privacySensitive()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Color.seekCard)

                    Button(action: onSync) {
                        HStack {
                            Label(savedKey.isEmpty ? "连接 NodeImage" : "同步密钥", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncing {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(!ownsLibrary || isBusy)
                    .listRowBackground(Color.seekCard)
                    .accessibilityIdentifier("nodeimage-sheet-sync")

                    Button {
                        confirmsRotate = true
                    } label: {
                        HStack {
                            Label("更新密钥", systemImage: "key.radiowaves.forward")
                            Spacer()
                            if isRotating {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(!ownsLibrary || isBusy)
                    .listRowBackground(Color.seekCard)
                    .accessibilityIdentifier("nodeimage-sheet-rotate")
                }

                Section {
                    HStack(spacing: 8) {
                        Group {
                            if revealsKey {
                                TextField("粘贴 32–128 位十六进制密钥", text: $draftKey)
                            } else {
                                SecureField("粘贴 32–128 位十六进制密钥", text: $draftKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .privacySensitive()
                        .accessibilityIdentifier("nodeimage-key-field")

                        if !draftKey.isEmpty {
                            Button {
                                revealsKey.toggle()
                            } label: {
                                Image(systemName: revealsKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(revealsKey ? "隐藏密钥" : "显示密钥")
                        }
                    }
                    .listRowBackground(Color.seekCard)

                    Button(action: onSaveKey) {
                        HStack {
                            Text("保存密钥")
                            Spacer()
                            if isSaving {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(!canSaveDraft)
                    .listRowBackground(Color.seekCard)
                    .accessibilityIdentifier("nodeimage-save-key")
                } header: {
                    Text("手动设置密钥")
                } footer: {
                    if let validationError {
                        Text(validationError)
                            .foregroundStyle(.red)
                    } else if !trimmedDraft.isEmpty && trimmedDraft == savedKey {
                        Text("该密钥与本机当前保存的密钥相同。")
                    } else {
                        Text("粘贴已有 API Key 后会先验证可用性，再加密保存在本机钥匙串中。")
                    }
                }

                if !savedKey.isEmpty {
                    Section {
                        Button("移除本机密钥", role: .destructive) {
                            confirmsRemove = true
                        }
                        .disabled(!ownsLibrary || isBusy)
                        .listRowBackground(Color.seekCard)
                        .accessibilityIdentifier("nodeimage-remove-key")
                    } footer: {
                        Text("仅清除本机保存的密钥，不影响已上传到 NodeImage 的图片。")
                    }
                }
            }
            .seekCanvas()
            .listSectionSpacing(20)
            .navigationTitle("密钥管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .disabled(isSaving || isSyncing || isRotating)
                }
            }
            .alert("更新 NodeImage 密钥？", isPresented: $confirmsRotate) {
                Button("更新密钥", role: .destructive, action: onRotate)
                Button("取消", role: .cancel) {}
            } message: {
                Text("更新后旧密钥会失效，使用旧密钥的工具也需要换成新密钥。")
            }
            .alert("移除本机密钥？", isPresented: $confirmsRemove) {
                Button("移除本机密钥", role: .destructive) {
                    onRemoveKey()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("移除后需要重新连接或填写密钥才能上传和管理图片。")
            }
        }
        .presentationDetents([.fraction(0.72), .large])
    }
}
