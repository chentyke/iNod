import NodeSeekCore
import SwiftUI

struct SeekSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }.pickerStyle(.menu)
        } else {
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        Text(label(option)).font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == option ? Color.seekInk : .secondary)
                            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 36)
                            .background(selection == option ? Color.seekCard : .clear, in: .capsule)
                    }
                    .buttonStyle(.seekRow)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(4).background(Color.seekTray.opacity(0.65), in: .capsule)
            .accessibilityElement(children: .contain).accessibilityLabel(title)
        }
    }
}

#Preview("Light") {
    @Previewable @State var sort = FeedSort.replyTime
    VStack(spacing: 24) {
        SeekSectionTitle(title: "社区", detail: "NodeSeek")
        SeekSegmentedPicker(title: "排序", selection: $sort, options: FeedSort.allCases, label: { $0.title })
        HStack { SeekIconTile(symbol: .inkReplyCount); SeekCategoryLabel(title: "技术", category: "tech") }
        Button("写回复", image: .inkReply) { }.buttonStyle(.seekPill)
        Button("查看主题") { }.buttonStyle(.seekPill(primary: false))
    }.padding(24).seekCanvas()
}
