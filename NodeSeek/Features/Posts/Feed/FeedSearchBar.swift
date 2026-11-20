import SwiftUI

struct FeedSearchBar: View {
    @Binding var query: String
    let isExpanded: Bool
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onOpen: () -> Void
    let onClose: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var symbolSize = 16.0

    var body: some View {
        HStack(spacing: 0) {
            Button(action: isExpanded ? onClose : onOpen) {
                Image(isExpanded ? .inkClose : .inkSearchPosts)
                    .resizable().scaledToFit()
                    .frame(width: symbolSize, height: symbolSize)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.seekButtonIcon)
            .accessibilityLabel("关闭搜索")
            .accessibilityHidden(!isExpanded)
            TextField("搜索帖子", text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused(focus)
                .onSubmit(onSubmit)
                .frame(minHeight: 48)
                .allowsHitTesting(isExpanded)
                // A folded field can't take focus, so returning to the feed never brings the keyboard back.
                .disabled(!isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .font(.subheadline)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity)
        .overlay {
            if !isExpanded {
                Button(action: onOpen) {
                    Color.clear.contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("搜索帖子")
                .transition(.identity)
            }
        }
    }
}
