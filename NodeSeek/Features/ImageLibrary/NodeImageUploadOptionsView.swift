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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("图片处理") {
                    Toggle("压缩图片", isOn: $compressImages)
                    if compressImages {
                        LabeledContent("压缩质量", value: compressionQuality.formatted(.number.precision(.fractionLength(0))) + "%")
                        Slider(value: $compressionQuality, in: 10...100, step: 5)
                            .accessibilityLabel("压缩质量")
                    }
                    Toggle("添加水印", isOn: $addWatermark)
                    if addWatermark {
                        Toggle("NodeImage 网址", isOn: $watermarkWebsite)
                        Toggle("论坛用户名", isOn: $watermarkUsername)
                    }
                }
                Section {
                    Toggle("上传后复制链接", isOn: $copyAfterUpload)
                    if copyAfterUpload {
                        Picker("链接格式", selection: $linkFormat) {
                            ForEach(HostedImageLinkFormat.allCases, id: \.self) { format in
                                Text(format.title).tag(format)
                            }
                        }
                    }
                }
                Section {
                    Toggle("到期自动删除", isOn: $autoDelete)
                    if autoDelete {
                        Stepper("\(deleteDays) 天后删除", value: $deleteDays, in: 1...365)
                    }
                }
            }
            .seekGroupedList()
            .navigationTitle("上传选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
