import NodeSeekCore
import SwiftUI

struct NodeImageUploadOptionsView: View {
    @Binding var compressImages: Bool
    @Binding var compressionQuality: Double
    @Binding var addWatermark: Bool
    @Binding var watermarkWebsite: Bool
    @Binding var watermarkUsername: Bool
    @Binding var copyAfterUpload: Bool
    @Binding var linkFormat: HostedImageLinkFormat
    @Binding var autoDelete: Bool
    @Binding var deleteDays: Int
    var onReset: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var currentConfig: NodeImageUploadConfig {
        NodeImageUploadConfig(
            compressImages: compressImages,
            compressionQuality: compressionQuality,
            addWatermark: addWatermark,
            watermarkWebsite: watermarkWebsite,
            watermarkUsername: watermarkUsername,
            copyAfterUpload: copyAfterUpload,
            linkFormat: linkFormat,
            autoDelete: autoDelete,
            deleteDays: deleteDays
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("压缩图片", isOn: $compressImages).tint(Color.seekGreen)
                        .listRowBackground(Color.seekCard)

                    if compressImages {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("压缩质量")
                                    .foregroundStyle(Color.seekInk)
                                Spacer()
                                Text("\(currentConfig.clampedQuality)%")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $compressionQuality, in: 10...100, step: 5)
                                .accessibilityLabel("压缩质量")
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.seekCard)
                    }

                    Toggle("添加水印", isOn: $addWatermark).tint(Color.seekGreen)
                        .listRowBackground(Color.seekCard)

                    if addWatermark {
                        Toggle("NodeImage 网址", isOn: $watermarkWebsite).tint(Color.seekGreen)
                            .listRowBackground(Color.seekCard)
                        Toggle("论坛用户名", isOn: $watermarkUsername).tint(Color.seekGreen)
                            .listRowBackground(Color.seekCard)
                    }
                } header: {
                    Text("图片处理")
                } footer: {
                    if currentConfig.hasMissingWatermarkContent {
                        Text("请至少勾选一项水印内容，否则上传时不会绘制水印。")
                            .foregroundStyle(.red)
                    } else if compressImages {
                        Text("不透明图片会转为 JPEG 压缩；带透明通道的图片会保留 PNG 透明效果并按比例缩放。")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("默认链接格式")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        let columns = Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: typeSize.isAccessibilitySize ? 1 : 2
                        )
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(HostedImageLinkFormat.allCases, id: \.self) { format in
                                let isSelected = linkFormat == format
                                Button {
                                    linkFormat = format
                                } label: {
                                    Text(format.title)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .lineLimit(1)
                                        .foregroundStyle(isSelected ? Color.seekOnInk : Color.seekInk)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .padding(.horizontal, 10)
                                        .background(isSelected ? Color.seekInk : Color.seekTray, in: .capsule)
                                }
                                .buttonStyle(.seekRow)
                                .accessibilityIdentifier("nodeimage-format-\(format.rawValue)")
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.seekCard)

                    Toggle("上传后复制链接", isOn: $copyAfterUpload).tint(Color.seekGreen)
                        .listRowBackground(Color.seekCard)
                } header: {
                    Text("链接与复制")
                } footer: {
                    Text("默认格式同时作用于列表快捷复制、左滑复制以及编辑器自动复制。")
                }

                Section {
                    Toggle("到期自动删除", isOn: $autoDelete).tint(Color.seekGreen)
                        .listRowBackground(Color.seekCard)

                    if autoDelete {
                        let columns = Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: typeSize.isAccessibilitySize ? 2 : 3
                        )
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(NodeImageUploadConfig.expirationPresets, id: \.self) { preset in
                                let isSelected = deleteDays == preset
                                Button {
                                    deleteDays = preset
                                } label: {
                                    Text("\(preset) 天")
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(isSelected ? Color.seekOnInk : Color.seekInk)
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                        .background(isSelected ? Color.seekInk : Color.seekTray, in: .capsule)
                                }
                                .buttonStyle(.seekRow)
                                .accessibilityIdentifier("nodeimage-expire-\(preset)")
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.seekCard)

                        Stepper("\(deleteDays) 天后删除", value: $deleteDays, in: 1...365)
                            .monospacedDigit()
                            .listRowBackground(Color.seekCard)
                    }
                } header: {
                    Text("保存期限")
                }

                if !currentConfig.isDefault, let onReset {
                    Section {
                        Button("恢复默认选项", action: onReset)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityIdentifier("nodeimage-options-reset")
                    }
                    .listRowBackground(Color.seekCard)
                }
            }
            .seekCanvas()
            .listSectionSpacing(20)
            .navigationTitle("上传选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("nodeimage-options-done")
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
    }
}
