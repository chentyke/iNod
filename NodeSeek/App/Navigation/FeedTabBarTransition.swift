import SwiftUI
import UIKit

struct FeedTabBarTransition: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { }

    final class Controller: UIViewController {
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            updateTabBar(hidesBar: false, animated: animated)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Restore the bar if the transition left it hidden when the feed returned.
            guard let navigation = navigationController,
                  let root = navigation.viewControllers.first,
                  navigation.topViewController === root,
                  let tabs = navigation.tabBarController,
                  tabs.isTabBarHidden else { return }
            tabs.setTabBarHidden(false, animated: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            updateTabBar(hidesBar: true, animated: animated)
        }

        private func updateTabBar(hidesBar: Bool, animated: Bool) {
            guard let navigation = navigationController,
                  let transition = navigation.transitionCoordinator,
                  let root = navigation.viewControllers.first,
                  let from = transition.viewController(forKey: .from),
                  let to = transition.viewController(forKey: .to),
                  (hidesBar ? from : to) === root,
                  (hidesBar ? to : from).preferredTransition != nil,
                  let tabs = navigation.tabBarController else { return }

            let animatesBar = animated && !UIAccessibility.isReduceMotionEnabled
            if !hidesBar && transition.isInteractive {
                // Reveal the tab bar as the card shrinks away after the gesture commits.
                transition.notifyWhenInteractionChanges { [weak tabs] context in
                    guard !context.isCancelled, let tabs, tabs.isTabBarHidden else { return }
                    tabs.setTabBarHidden(false, animated: animatesBar)
                }
            } else if tabs.isTabBarHidden != hidesBar {
                tabs.setTabBarHidden(hidesBar, animated: animatesBar)
            }
        }
    }
}
