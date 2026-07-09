#if os(iOS) || os(tvOS)
  import SceneKit
  import SpriteKit
  import UIKit
  #if os(iOS)
    import WebKit
  #endif

  // The iOS/tvOS render engine: the async, protocol-free port of the UIKit half of the legacy
  // `Common/View.swift` (`prepareView`/`snapshotView`/`addImagesForRenderedViews`). Everything here
  // is `@MainActor`; because snapshot assertions run on the main actor, the synchronous prefix of a
  // capture runs eagerly in the caller's turn, and only the genuinely-async web snapshot suspends.

  /// Stages a view (or view controller) in a window with the requested size, safe area, and traits,
  /// returning a closure that tears the staging back down. Ported verbatim from the legacy
  /// `prepareView`.
  @MainActor
  func prepareView(
    config: ViewImageConfig,
    drawHierarchyInKeyWindow: Bool,
    traits: UITraitCollection,
    view: UIView,
    viewController: UIViewController
  ) -> () -> Void {
    let size = config.size ?? viewController.view.frame.size
    view.frame.size = size
    if view != viewController.view {
      viewController.view.bounds = view.bounds
      viewController.view.addSubview(view)
    }
    let traits = UITraitCollection(traitsFrom: [config.traits, traits])
    let window: UIWindow
    if drawHierarchyInKeyWindow {
      guard let keyWindow = getKeyWindow() else {
        fatalError("'drawHierarchyInKeyWindow' requires tests to be run in a host application")
      }
      window = keyWindow
      window.frame.size = size
    } else {
      window = Window(
        config: .init(safeArea: config.safeArea, size: config.size ?? size, traits: traits),
        viewController: viewController
      )
    }
    let dispose = add(traits: traits, viewController: viewController, to: window)

    if size.width == 0 || size.height == 0 {
      // Try to call sizeToFit() if the view still has invalid size
      view.sizeToFit()
      view.setNeedsLayout()
      view.layoutIfNeeded()
    }

    return dispose
  }

  /// Stages the view, captures it, and tears the staging down — the async form of the legacy
  /// `snapshotView`. Views that can only snapshot themselves asynchronously (`WKWebView` and
  /// friends) suspend inside `asyncSnapshotImage`/`renderedSubviewImages`; everything else renders
  /// synchronously in the caller's main-actor turn.
  @MainActor
  func snapshotView(
    config: ViewImageConfig,
    drawHierarchyInKeyWindow: Bool,
    traits: UITraitCollection,
    view: UIView,
    viewController: UIViewController
  ) async -> UIImage {
    let initialFrame = view.frame
    let dispose = prepareView(
      config: config,
      drawHierarchyInKeyWindow: drawHierarchyInKeyWindow,
      traits: traits,
      view: view,
      viewController: viewController
    )
    defer { dispose() }
    // NB: Avoid safe area influence.
    if config.safeArea == .zero { view.frame.origin = .init(x: offscreen, y: offscreen) }

    if let image = await view.asyncSnapshotImage() {
      return image
    }
    let overlays = await renderedSubviewImages(of: view)
    let image = renderer(bounds: view.bounds, for: traits).image { ctx in
      if drawHierarchyInKeyWindow {
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
      } else {
        view.layer.render(in: ctx.cgContext)
      }
    }
    overlays.forEach { $0.removeFromSuperview() }
    view.frame = initialFrame
    return image
  }

  private let offscreen: CGFloat = 10_000

  func renderer(bounds: CGRect, for traits: UITraitCollection) -> UIGraphicsImageRenderer {
    UIGraphicsImageRenderer(bounds: bounds, format: .init(for: traits))
  }

  /// Overlays freshly-rendered images for any subviews that can only snapshot themselves
  /// asynchronously, returning the overlay views so the caller can remove them after rendering.
  /// The iOS analog of the macOS engine's function of the same name.
  @MainActor
  func renderedSubviewImages(of view: UIView) async -> [UIView] {
    if let image = await view.asyncSnapshotImage() {
      let imageView = UIImageView()
      imageView.image = image
      imageView.frame = view.frame
      view.superview?.insertSubview(imageView, aboveSubview: view)
      return [imageView]
    } else {
      var added: [UIView] = []
      for subview in view.subviews {
        added += await renderedSubviewImages(of: subview)
      }
      return added
    }
  }

  extension UIView {
    /// Snapshots views that render off the normal `layer.render` path. Returns `nil` for ordinary
    /// views. The `WKWebView` case (iOS only) is the genuinely asynchronous one, bridged from its
    /// callback API with a checked continuation.
    @MainActor
    func asyncSnapshotImage() async -> UIImage? {
      if let scnView = self as? SCNView {
        return scnView.snapshot()
      } else if let skView = self as? SKView {
        guard let scene = skView.scene, let texture = skView.texture(from: scene) else {
          return nil
        }
        return UIImage(cgImage: texture.cgImage())
      }
      #if os(iOS)
        if let wkWebView = self as? WKWebView {
          if wkWebView.isLoading {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
              _ = WebViewLoadObserver(wkWebView) { continuation.resume() }
            }
          }
          return await withCheckedContinuation {
            (continuation: CheckedContinuation<UIImage?, Never>) in
            guard wkWebView.frame.width != 0, wkWebView.frame.height != 0 else {
              continuation.resume(returning: UIImage())
              return
            }
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = false
            wkWebView.takeSnapshot(with: configuration) { image, _ in
              continuation.resume(returning: image)
            }
          }
        }
      #endif
      return nil
    }
  }

  extension UIApplication {
    static var sharedIfAvailable: UIApplication? {
      let sharedSelector = NSSelectorFromString("sharedApplication")
      guard UIApplication.responds(to: sharedSelector) else {
        return nil
      }
      // Legacy force-cast softened: a non-`UIApplication` result degrades to "no application".
      return UIApplication.perform(sharedSelector)?.takeUnretainedValue() as? UIApplication
    }
  }

  @MainActor
  private func getKeyWindow() -> UIWindow? {
    UIApplication.sharedIfAvailable?.windows.first { $0.isKeyWindow }
  }

  /// Parents the controller (re-rooting under a fresh container when needed), applies traits, and
  /// drives the appearance transitions — returning the closure that reverses it all. Ported
  /// verbatim from the legacy `add(traits:viewController:to:)`.
  @MainActor
  private func add(
    traits: UITraitCollection, viewController: UIViewController, to window: UIWindow
  ) -> () -> Void {
    let rootViewController: UIViewController
    if viewController != window.rootViewController {
      rootViewController = UIViewController()
      rootViewController.view.backgroundColor = .clear
      rootViewController.view.frame = window.frame
      rootViewController.view.translatesAutoresizingMaskIntoConstraints =
        viewController.view.translatesAutoresizingMaskIntoConstraints
      rootViewController.preferredContentSize = rootViewController.view.frame.size
      viewController.view.frame = rootViewController.view.frame
      rootViewController.view.addSubview(viewController.view)
      if viewController.view.translatesAutoresizingMaskIntoConstraints {
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      } else {
        NSLayoutConstraint.activate([
          viewController.view.topAnchor.constraint(equalTo: rootViewController.view.topAnchor),
          viewController.view.bottomAnchor.constraint(
            equalTo: rootViewController.view.bottomAnchor),
          viewController.view.leadingAnchor.constraint(
            equalTo: rootViewController.view.leadingAnchor),
          viewController.view.trailingAnchor.constraint(
            equalTo: rootViewController.view.trailingAnchor),
        ])
      }
      rootViewController.addChild(viewController)
    } else {
      rootViewController = viewController
    }
    rootViewController.setOverrideTraitCollection(traits, forChild: viewController)
    viewController.didMove(toParent: rootViewController)

    window.rootViewController = rootViewController

    rootViewController.beginAppearanceTransition(true, animated: false)
    rootViewController.endAppearanceTransition()

    rootViewController.view.setNeedsLayout()
    rootViewController.view.layoutIfNeeded()

    viewController.view.setNeedsLayout()
    viewController.view.layoutIfNeeded()

    return {
      rootViewController.beginAppearanceTransition(false, animated: false)
      viewController.willMove(toParent: nil)
      viewController.view.removeFromSuperview()
      viewController.removeFromParent()
      viewController.didMove(toParent: nil)
      rootViewController.endAppearanceTransition()
      window.rootViewController = nil
    }
  }

  private final class Window: UIWindow {
    var config: ViewImageConfig

    init(config: ViewImageConfig, viewController: UIViewController) {
      let size = config.size ?? viewController.view.bounds.size
      self.config = config
      super.init(frame: .init(origin: .zero, size: size))

      // NB: Safe area renders inaccurately for UI{Navigation,TabBar}Controller.
      // Fixes welcome!
      if viewController is UINavigationController {
        self.frame.size.height -= self.config.safeArea.top
        self.config.safeArea.top = 0
      } else if let viewController = viewController as? UITabBarController {
        self.frame.size.height -= self.config.safeArea.bottom
        self.config.safeArea.bottom = 0
        if viewController.selectedViewController is UINavigationController {
          self.frame.size.height -= self.config.safeArea.top
          self.config.safeArea.top = 0
        }
      }
      self.isHidden = false
    }

    required init?(coder aDecoder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override var safeAreaInsets: UIEdgeInsets {
      #if os(iOS)
        let removeTopInset =
          self.config.safeArea == .init(top: 20, left: 0, bottom: 0, right: 0)
          && self.rootViewController?.prefersStatusBarHidden ?? false
        if removeTopInset { return .zero }
      #endif
      return self.config.safeArea
    }
  }
#endif
