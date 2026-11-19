import SwiftUI
import UIKit

/// Observe taps at the window so native navigation controls and the margins around the composer count too.
struct ReplyOutsideTap: UIViewRepresentable {
    let cornerRadius: CGFloat
    let onTap: () -> Void

    func makeUIView(context: Context) -> Observer {
        let view = Observer()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Observer, context: Context) {
        view.cornerRadius = cornerRadius
        view.onTap = onTap
    }

    static func dismantleUIView(_ view: Observer, coordinator: ()) { view.stop() }

    final class Observer: UIView, UIGestureRecognizerDelegate {
        var cornerRadius: CGFloat = 0
        var onTap: (() -> Void)?
        private lazy var tap: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissReply))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            return tap
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            window?.addGestureRecognizer(tap)
        }

        func stop() { tap.view?.removeGestureRecognizer(tap) }
        @objc private func dismissReply() { onTap?() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window, touch.view?.window === window,
                  !window.keyboardLayoutGuide.layoutFrame.contains(touch.location(in: window)) else { return false }
            return !UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).contains(touch.location(in: self))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
