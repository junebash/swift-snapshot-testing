#if os(iOS) || os(tvOS)
  import UIKit

  // MARK: - UIView

  /// Renders a view to an image and compares by pixel equality. The protocol form of
  /// `Snapshotting<UIView, UIImage>.image`.
  ///
  /// Like `NSViewImageStrategy`, this is a `@MainActor` witness satisfying the
  /// `nonisolated(nonsending)` requirement: assertions run on the main actor, so the render runs
  /// eagerly in the caller's turn, suspending only for genuinely-async captures (`WKWebView`).
  public struct UIViewImageStrategy: SnapshotStrategy {
    public typealias Value = UIView
    public typealias Format = UIImage

    let drawHierarchyInKeyWindow: Bool
    let precision: Float
    let perceptualPrecision: Float
    let size: CGSize?
    let traits: UITraitCollection

    public init(
      drawHierarchyInKeyWindow: Bool = false,
      precision: Float = 1,
      perceptualPrecision: Float = 1,
      size: CGSize? = nil,
      traits: UITraitCollection = .init()
    ) {
      self.drawHierarchyInKeyWindow = drawHierarchyInKeyWindow
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
      self.size = size
      self.traits = traits
    }

    public var pathExtension: String? { "png" }
    public var diffing: UIImageDiffing {
      UIImageDiffing(
        precision: precision, perceptualPrecision: perceptualPrecision,
        scale: traits.displayScale)
    }

    @MainActor
    public func snapshot(of view: sending UIView) async -> sending UIImage {
      await snapshotView(
        config: .init(safeArea: .zero, size: size ?? view.frame.size, traits: .init()),
        drawHierarchyInKeyWindow: drawHierarchyInKeyWindow,
        traits: traits,
        view: view,
        viewController: .init()
      )
    }
  }

  extension SnapshotStrategy where Self == UIViewImageStrategy {
    /// A snapshot strategy for comparing views based on pixel equality.
    public static var image: UIViewImageStrategy { UIViewImageStrategy() }

    /// A snapshot strategy for comparing views based on pixel equality.
    ///
    /// - Parameters:
    ///   - drawHierarchyInKeyWindow: Utilize the simulator's key window in order to render
    ///     `UIAppearance` and `UIVisualEffect`s. This option requires a host application for your
    ///     tests and will _not_ work for framework test targets.
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered
    ///     a match.
    ///   - size: A view size override.
    ///   - traits: A trait collection override.
    public static func image(
      drawHierarchyInKeyWindow: Bool = false,
      precision: Float = 1,
      perceptualPrecision: Float = 1,
      size: CGSize? = nil,
      traits: UITraitCollection = .init()
    ) -> UIViewImageStrategy {
      UIViewImageStrategy(
        drawHierarchyInKeyWindow: drawHierarchyInKeyWindow,
        precision: precision,
        perceptualPrecision: perceptualPrecision,
        size: size,
        traits: traits
      )
    }
  }

  extension SnapshotStrategy where Self == _Pullback<UIView, LinesStrategy> {
    /// A snapshot strategy for comparing views based on a recursive description of their properties
    /// and hierarchies.
    ///
    /// ``` swift
    /// // Layout on the current device.
    /// await assertSnapshot(of: view, as: .recursiveDescription)
    ///
    /// // Layout with a certain size.
    /// await assertSnapshot(of: view, as: .recursiveDescription(size: .init(width: 22, height: 22)))
    /// ```
    public static var recursiveDescription: _Pullback<UIView, LinesStrategy> {
      .recursiveDescription()
    }

    /// A snapshot strategy for comparing views based on a recursive description of their properties
    /// and hierarchies.
    public static func recursiveDescription(
      size: CGSize? = nil,
      traits: UITraitCollection = .init()
    ) -> _Pullback<UIView, LinesStrategy> {
      LinesStrategy().pullback { (view: UIView) -> String in
        let dispose = prepareView(
          config: .init(safeArea: .zero, size: size ?? view.frame.size, traits: traits),
          drawHierarchyInKeyWindow: false,
          traits: .init(),
          view: view,
          viewController: .init()
        )
        defer { dispose() }
        // `recursiveDescription` is UIKit's private hierarchy dump — same selector the legacy
        // witness used; a runtime surprise degrades to a diffable marker rather than trapping.
        let description =
          view.perform(Selector(("recursiveDescription"))).retain().takeUnretainedValue()
          as? String
        return purgePointers(description ?? "<no recursiveDescription>")
      }
    }
  }

  // MARK: - UIViewController

  /// Renders a view controller's view to an image and compares by pixel equality. The protocol
  /// form of `Snapshotting<UIViewController, UIImage>.image`.
  public struct UIViewControllerImageStrategy: SnapshotStrategy {
    public typealias Value = UIViewController
    public typealias Format = UIImage

    let config: ViewImageConfig?
    let drawHierarchyInKeyWindow: Bool
    let precision: Float
    let perceptualPrecision: Float
    let size: CGSize?
    let traits: UITraitCollection

    public init(
      on config: ViewImageConfig? = nil,
      drawHierarchyInKeyWindow: Bool = false,
      precision: Float = 1,
      perceptualPrecision: Float = 1,
      size: CGSize? = nil,
      traits: UITraitCollection = .init()
    ) {
      self.config = config
      self.drawHierarchyInKeyWindow = drawHierarchyInKeyWindow
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
      self.size = size
      self.traits = traits
    }

    public var pathExtension: String? { "png" }
    public var diffing: UIImageDiffing {
      UIImageDiffing(
        precision: precision, perceptualPrecision: perceptualPrecision,
        scale: traits.displayScale)
    }

    @MainActor
    public func snapshot(of viewController: sending UIViewController) async -> sending UIImage {
      // Mirrors the two legacy `Snapshotting` variants: with a device config, a size override
      // replaces the config's size; without one, the size override *is* the config.
      let resolvedConfig: ViewImageConfig
      if let config {
        resolvedConfig =
          size.map { .init(safeArea: config.safeArea, size: $0, traits: config.traits) } ?? config
      } else {
        resolvedConfig = .init(safeArea: .zero, size: size, traits: traits)
      }
      return await snapshotView(
        config: resolvedConfig,
        drawHierarchyInKeyWindow: drawHierarchyInKeyWindow,
        traits: traits,
        view: viewController.view,
        viewController: viewController
      )
    }
  }

  extension SnapshotStrategy where Self == UIViewControllerImageStrategy {
    /// A snapshot strategy for comparing view controller views based on pixel equality.
    public static var image: UIViewControllerImageStrategy { UIViewControllerImageStrategy() }

    /// A snapshot strategy for comparing view controller views based on pixel equality.
    ///
    /// - Parameters:
    ///   - config: A set of device configuration settings.
    ///   - drawHierarchyInKeyWindow: Utilize the simulator's key window in order to render
    ///     `UIAppearance` and `UIVisualEffect`s. This option requires a host application for your
    ///     tests and will _not_ work for framework test targets.
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered
    ///     a match.
    ///   - size: A view size override.
    ///   - traits: A trait collection override.
    public static func image(
      on config: ViewImageConfig,
      drawHierarchyInKeyWindow: Bool = false,
      precision: Float = 1,
      perceptualPrecision: Float = 1,
      size: CGSize? = nil,
      traits: UITraitCollection = .init()
    ) -> UIViewControllerImageStrategy {
      UIViewControllerImageStrategy(
        on: config,
        drawHierarchyInKeyWindow: drawHierarchyInKeyWindow,
        precision: precision,
        perceptualPrecision: perceptualPrecision,
        size: size,
        traits: traits
      )
    }

    /// A snapshot strategy for comparing view controller views based on pixel equality.
    public static func image(
      drawHierarchyInKeyWindow: Bool = false,
      precision: Float = 1,
      perceptualPrecision: Float = 1,
      size: CGSize? = nil,
      traits: UITraitCollection = .init()
    ) -> UIViewControllerImageStrategy {
      UIViewControllerImageStrategy(
        drawHierarchyInKeyWindow: drawHierarchyInKeyWindow,
        precision: precision,
        perceptualPrecision: perceptualPrecision,
        size: size,
        traits: traits
      )
    }
  }

  extension SnapshotStrategy where Self == _Pullback<UIViewController, LinesStrategy> {
    /// A snapshot strategy for comparing view controllers based on their embedded controller
    /// hierarchy.
    public static var hierarchy: _Pullback<UIViewController, LinesStrategy> {
      LinesStrategy().pullback { (viewController: UIViewController) -> String in
        let dispose = prepareView(
          config: .init(),
          drawHierarchyInKeyWindow: false,
          traits: .init(),
          view: viewController.view,
          viewController: viewController
        )
        defer { dispose() }
        let description =
          viewController.perform(Selector(("_printHierarchy"))).retain().takeUnretainedValue()
          as? String
        return purgePointers(description ?? "<no _printHierarchy>")
      }
    }

    /// A snapshot strategy for comparing view controller views based on a recursive description of
    /// their properties and hierarchies.
    public static var recursiveDescription: _Pullback<UIViewController, LinesStrategy> {
      .recursiveDescription()
    }

    /// A snapshot strategy for comparing view controller views based on a recursive description of
    /// their properties and hierarchies.
    ///
    /// - Parameters:
    ///   - config: A set of device configuration settings.
    ///   - size: A view size override.
    ///   - traits: A trait collection override.
    public static func recursiveDescription(
      on config: ViewImageConfig = .init(),
      size: CGSize? = nil,
      traits: UITraitCollection = .init()
    ) -> _Pullback<UIViewController, LinesStrategy> {
      LinesStrategy().pullback { (viewController: UIViewController) -> String in
        let dispose = prepareView(
          config: .init(
            safeArea: config.safeArea, size: size ?? config.size, traits: config.traits),
          drawHierarchyInKeyWindow: false,
          traits: traits,
          view: viewController.view,
          viewController: viewController
        )
        defer { dispose() }
        let description =
          viewController.view.perform(Selector(("recursiveDescription"))).retain()
            .takeUnretainedValue() as? String
        return purgePointers(description ?? "<no recursiveDescription>")
      }
    }
  }
#endif
