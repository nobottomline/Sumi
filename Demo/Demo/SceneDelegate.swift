import UIKit
import Sumi

// SceneDelegate — single-window setup.
//
// Builds `GalleryListViewController` from the central registry,
// wraps it in a UINavigationController, attaches as root.

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)

        let root = GalleryListViewController(entries: GalleryRegistry.allEntries)
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.tintColor = Sumi.Color.accent

        window.rootViewController = nav
        window.makeKeyAndVisible()
        self.window = window
    }
}
