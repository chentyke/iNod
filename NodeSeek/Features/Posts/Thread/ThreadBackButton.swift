import SwiftUI
import UIKit

/// A UIKit control takes priority over the zoom transition's swipe recognizer for a tap.
struct ThreadBackButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let symbol = UIImage.SymbolConfiguration(textStyle: .headline, scale: .medium)
        button.setImage(UIImage(resource: .inkBack).imageFlippedForRightToLeftLayoutDirection().applyingSymbolConfiguration(symbol), for: .normal)
        button.tintColor = UIColor(Color.seekButtonIcon)
        button.accessibilityLabel = "返回"
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.action()
        }, for: .primaryActionTriggered)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }
    }
}
