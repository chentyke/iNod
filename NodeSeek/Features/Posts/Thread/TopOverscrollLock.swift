import SwiftUI
import UIKit

/// Lets a swipe down close a zoomed post instead of fighting the scroll view.
/// The system swipe-down dismiss loses to the scroll view when the drag starts slowly or at an angle,
/// and while the page rubber-bands from that pull it keeps losing. So while a finger is down the page
/// can't be pulled past its top, and a pull the system didn't pick up closes the post itself.
struct TopOverscrollLock: UIViewRepresentable {
    func makeUIView(context: Context) -> LockView { LockView() }
    func updateUIView(_ view: LockView, context: Context) { }

    final class LockView: UIView {
        /// How far the finger travels past the top before the post closes.
        private static let closingPull: CGFloat = 50
        private var observation: NSKeyValueObservation?
        private weak var scrollView: UIScrollView?
        private var pullStart: CGFloat?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            let found = ancestor as? UIScrollView
            guard found !== scrollView else { return }
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(pan(_:)))
            scrollView = found
            found?.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
            observation = found?.observe(\.contentOffset) { [weak self] scrollView, _ in
                MainActor.assumeIsolated { self?.offsetChanged(scrollView) }
            }
        }

        @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began { pullStart = nil }
        }

        private func offsetChanged(_ scrollView: UIScrollView) {
            let top = -scrollView.adjustedContentInset.top
            guard scrollView.isTracking, scrollView.contentOffset.y < top,
                  let screen = zoomedScreen, let navigation = screen.navigationController,
                  navigation.topViewController === screen, navigation.transitionCoordinator == nil else { return }
            scrollView.contentOffset.y = top
            let finger = scrollView.panGestureRecognizer.translation(in: scrollView.superview).y
            let start = pullStart ?? finger
            pullStart = start
            if finger - start > Self.closingPull { navigation.popViewController(animated: true) }
        }

        /// The pushed screen this view sits in, when it was pushed with a zoom transition.
        private var zoomedScreen: UIViewController? {
            var responder: UIResponder? = self
            while let next = responder, !(next is UIViewController) { responder = next.next }
            var screen = responder as? UIViewController
            while let current = screen, !(current.parent is UINavigationController) { screen = current.parent }
            return screen?.preferredTransition == nil ? nil : screen
        }
    }
}
