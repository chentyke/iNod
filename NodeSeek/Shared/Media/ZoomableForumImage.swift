import SwiftUI
import UIKit

struct ZoomableForumImage: UIViewRepresentable {
    let image: CGImage
    let label: String
    let isCurrent: Bool
    let onZoomChanged: (Bool) -> Void
    let onDismiss: () -> Void
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> PhotoScrollView { PhotoScrollView() }

    func updateUIView(_ view: PhotoScrollView, context: Context) {
        view.onZoomChanged = onZoomChanged
        view.dismissSwipe.isEnabled = reduceMotion
        view.onDismiss = onDismiss
        view.onTap = onTap
        view.animatesZoom = !reduceMotion
        view.accessibilityLabel = label
        view.accessibilityElementsHidden = !isCurrent
        if view.photo.image?.cgImage !== image {
            view.photo.image = UIImage(cgImage: image)
            view.setNeedsLayout()
        }
        if !isCurrent, view.zoomScale != 1 { view.setZoomScale(1, animated: false) }
    }
}

final class PhotoScrollView: UIScrollView, UIScrollViewDelegate {
    let photo = UIImageView()
    var onZoomChanged: (Bool) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onDismiss: () -> Void = {}
    // The system zoom transition handles interactive dismissal when motion is enabled.
    let dismissSwipe = UISwipeGestureRecognizer()
    var animatesZoom = true
    private var fittedSize = CGSize.zero
    private var viewport = CGSize.zero
    private var zoomActive = false

    init() {
        super.init(frame: .zero)
        delegate = self
        maximumZoomScale = 6
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        scrollsToTop = false
        addSubview(photo)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
        addGestureRecognizer(doubleTap)
        dismissSwipe.direction = .down
        dismissSwipe.addTarget(self, action: #selector(swipedDown))
        addGestureRecognizer(dismissSwipe)

        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "放大图片", target: self, selector: #selector(enlarge)),
            UIAccessibilityCustomAction(name: "还原大小", target: self, selector: #selector(resetZoom))
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let size = photo.image?.size, size.width > 0, size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * fit, height: size.height * fit)
        if viewport != bounds.size || fittedSize != fitted {
            viewport = bounds.size
            fittedSize = fitted
            setZoomScale(1, animated: false)
            photo.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
        }
        centerPhoto()
    }

    override var accessibilityValue: String? {
        get { Double(zoomScale).formatted(.percent.precision(.fractionLength(0))) }
        set { super.accessibilityValue = newValue }
    }

    override func accessibilityActivate() -> Bool {
        onTap()
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === dismissSwipe, zoomActive { return false }
        if gestureRecognizer === panGestureRecognizer, !zoomActive { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerPhoto()
        setZoomActive(isZooming || zoomScale > 1.001)
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        setZoomActive(true)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        setZoomActive(scale > 1.001)
    }

    private func setZoomActive(_ active: Bool) {
        guard zoomActive != active else { return }
        zoomActive = active
        onZoomChanged(active)
    }

    private func centerPhoto() {
        photo.center = CGPoint(x: max(bounds.width, contentSize.width) / 2,
                               y: max(bounds.height, contentSize.height) / 2)
    }

    @objc private func swipedDown() { onDismiss() }
    @objc private func tapped() { onTap() }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        if zoomScale > 1.001 { resetZoom() }
        else { zoom(at: tap.location(in: photo), to: 2.5) }
    }

    @objc @discardableResult private func resetZoom() -> Bool {
        setZoomScale(1, animated: animatesZoom)
        return true
    }

    @objc private func enlarge() -> Bool {
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: photo)
        zoom(at: center, to: min(zoomScale * 2, maximumZoomScale))
        return true
    }

    private func zoom(at point: CGPoint, to scale: CGFloat) {
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let x = min(max(point.x, 0), photo.bounds.width)
        let y = min(max(point.y, 0), photo.bounds.height)
        zoom(to: CGRect(x: x - size.width / 2, y: y - size.height / 2,
                        width: size.width, height: size.height), animated: animatesZoom)
    }
}
