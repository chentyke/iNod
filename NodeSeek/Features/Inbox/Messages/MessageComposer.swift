import SwiftUI

struct MessageComposer: View {
    @Binding var text: String
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
                    Button("表情", image: .inkSticker, action: onStickers)
                    Button("预览", image: .inkPreviewMail, action: onPreview)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } label: {
                    Label("私信选项", image: .inkMailActions)
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.seekButtonIcon)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                        .glassEffect(.regular, in: .circle)
                }
                .menuOrder(.fixed)
                .disabled(isBusy)

                TextField("写私信", text: $text, axis: .vertical)
                    .accessibilityLabel("写私信")
                    .lineLimit(1...5)
                    .focused(focus)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .disabled(isBusy)
                    .glassEffect(.regular.interactive(!isBusy), in: .rect(cornerRadius: 22))

                Button(action: onSend) {
                    Label(isBusy ? "发送中" : "发送", image: .inkSendMail)
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSend ? Color.seekButtonIconOnFill : .seekButtonIcon)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isBusy ? "发送中" : "发送")
                .disabled(!canSend)
                .glassEffect(.regular.tint(canSend ? Color.seekInk : nil).interactive(canSend), in: .circle)
            }
        }
        .padding(.horizontal, SeekLayout.gutter)
        .padding(.vertical, 8)
        .readableColumn()
    }
}
