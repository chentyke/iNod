import SwiftUI
import UIKit

/// Recognizes a page swipe alongside the list or scroll view's own pan gesture.
struct PageSwipe: UIGestureRecognizerRepresentable {
    enum Direction {
        case left, right

        func distance(_ offset: CGPoint) -> CGFloat {
            self == .left ? -offset.x : offset.x
        }
    }

    static let minimumDistance: CGFloat = 100

    let direction: Direction
    var isEnabled = true
    var onMove: ((CGFloat) -> Void)? = nil
    let onEnd: (Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(direction: direction)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = isEnabled
        recognizer.maximumNumberOfTouches = 1
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.direction = direction
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        let distance = direction.distance(translation)
        switch recognizer.state {
        case .changed:
            onMove?(distance)
        case .ended:
            onEnd(distance >= Self.minimumDistance && distance > abs(translation.y) * 1.5)
        case .cancelled:
            onEnd(false)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var direction: Direction

        init(direction: Direction) {
            self.direction = direction
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return direction.distance(velocity) > abs(velocity.y) * 1.5
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Leave horizontal Markdown scrolling and text editing to the control under the finger.
            var current = touch.view
            while let view = current, view !== gestureRecognizer.view {
                if view is UITextField { return false }
                if let text = view as? UITextView, text.selectedRange.length > 0 { return false }
                if let scroll = view as? UIScrollView, scroll.isScrollEnabled {
                    let insets = scroll.adjustedContentInset
                    if scroll.contentSize.width + insets.left + insets.right > scroll.bounds.width + 1 {
                        return false
                    }
                }
                current = view.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}
