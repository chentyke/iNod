import NodeSeekCore
import SwiftUI

struct FeedSortPicker: View {
    @Binding var selection: FeedSort
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            } else {
                picker.pickerStyle(.segmented)
                    .frame(minHeight: 44)
            }
        }
        .controlSize(.large)
    }

    private var picker: some View {
        Picker("排序", selection: $selection) {
            ForEach(FeedSort.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }
}
