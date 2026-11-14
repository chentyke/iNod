import NodeSeekCore
import SwiftUI

struct StickerPickerView: View {
    let onSelect: (ForumSticker) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var group = "xhj"
    var body: some View {
        NavigationStack {
            VStack {
                Picker("表情分组", selection: $group) {
                    Text("小黄鸡").tag("xhj"); Text("AC娘").tag("ac"); Text("洋葱头").tag("yct"); Text("Fluent").tag("emoji")
                }.pickerStyle(.segmented).padding(.horizontal, 20)
                ScrollView {
                    LazyVGrid(columns: [.init(.adaptive(minimum: 56))], spacing: 16) {
                        ForEach(ForumSticker.all(in: group), id: \.code) { sticker in
                            Button { onSelect(sticker); dismiss() } label: { StickerThumbnail(sticker: sticker) }
                                .buttonStyle(.plain).accessibilityLabel("插入表情 \(sticker.code)")
                        }
                    }.padding(20)
                }
            }
            .seekCanvas()
            .navigationTitle("表情").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }.presentationDetents([.medium, .large])
    }
}
