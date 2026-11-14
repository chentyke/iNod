import NodeSeekCore
import SwiftUI

struct MessageComposer: View {
    @Binding var draft: MessageDraft
    let isBusy: Bool
    let canSend: Bool
    var focus: FocusState<Bool>.Binding
    let onStickers: () -> Void
    let onPreview: () -> Void
    let onSend: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Toggle("Markdown", isOn: $draft.isMarkdown)
                    Button("表情", systemImage: "face.smiling", action: onStickers)
                    if draft.isMarkdown {
                        Button("预览", systemImage: "eye", action: onPreview)
                            .disabled(draft.content.isEmpty)
                    }
                } label: {
                    Label("私信选项", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(draft.isMarkdown ? Color.seekGreen : Color.seekInk)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .disabled(isBusy)
                .accessibilityValue(draft.isMarkdown ? "Markdown 已开启" : "Markdown 已关闭")
                .glassEffect(.regular.interactive(!isBusy), in: .circle)

                TextField("写私信", text: $draft.content, axis: .vertical)
                    .accessibilityLabel("写私信")
                    .lineLimit(1...5)
                    .focused(focus)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .disabled(isBusy)
                    .glassEffect(.regular.interactive(!isBusy), in: .rect(cornerRadius: 22))

                Button(action: onSend) {
                    Label(isBusy ? "发送中" : "发送", systemImage: "arrow.up")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSend ? Color.seekOnInk : .secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isBusy ? "发送中" : "发送")
                .disabled(!canSend)
                .glassEffect(.regular.tint(canSend ? Color.seekInk : nil).interactive(canSend), in: .circle)
            }
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
