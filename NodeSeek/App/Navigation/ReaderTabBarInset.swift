import SwiftUI
import UIKit

/// Keeps the native tab controller at window size while centering its top bar over the reader.
struct ReaderTabBarInset: UIViewControllerRepresentable {
    let amount: CGFloat

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.amount = amount
        controller.applyInset()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Void) {
        controller.removeInset()
    }

    final class Controller: UIViewController {
        var amount: CGFloat = 0
        private weak var owner: UITabBarController?
        private var applied = UIEdgeInsets.zero

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyInset()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyInset()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            removeInset()
        }

        func applyInset() {
            let tabs = tabBarController
            if owner !== tabs {
                removeInset()
                owner = tabs
            }
            guard let tabs else { return }
            var inset = UIEdgeInsets.zero
            if tabs.view.effectiveUserInterfaceLayoutDirection == .rightToLeft {
                inset.right = amount
            } else {
                inset.left = amount
            }
            setInset(inset, on: tabs)
        }

        func removeInset() {
            setInset(.zero, on: owner)
        }

        private func setInset(_ inset: UIEdgeInsets, on tabs: UITabBarController?) {
            guard let tabs, inset != applied else { return }
            var area = tabs.additionalSafeAreaInsets
            area.left += inset.left - applied.left
            area.right += inset.right - applied.right
            applied = inset
            tabs.additionalSafeAreaInsets = area
        }
    }
}
