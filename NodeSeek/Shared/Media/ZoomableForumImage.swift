import SwiftUI

struct ZoomableForumImage: View {
    let image: CGImage
    let label: Text
    let isCurrent: Bool
    let onZoomChanged: (Bool) -> Void

    @State private var scale = 1.0
    @State private var offset = CGSize.zero
    @GestureState private var magnification = 1.0
    @GestureState private var translation = CGSize.zero

    var body: some View {
        Image(image, scale: 1, label: label).resizable().scaledToFit()
            .scaleEffect(min(6, max(1, scale * magnification)))
            .offset(x: offset.width + translation.width, y: offset.height + translation.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(pan, isEnabled: scale > 1)
            .simultaneousGesture(magnify)
            .onTapGesture(count: 2) { setScale(scale == 1 ? 2 : 1) }
            .accessibilityAction(named: "放大图片") { setScale(scale + 1) }
            .accessibilityAction(named: "还原大小") { setScale(1) }
            .onChange(of: isCurrent) { _, current in
                if !current { setScale(1) }
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onEnded { setScale(scale * $0.magnification) }
    }

    private var pan: some Gesture {
        DragGesture()
            .updating($translation) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private func setScale(_ value: Double) {
        scale = min(6, max(1, value))
        if scale == 1 { offset = .zero }
        onZoomChanged(scale > 1)
    }
}
