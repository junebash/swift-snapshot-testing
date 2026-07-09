#if os(macOS)
  import Cocoa

  /// Renders a view controller's view to an image and compares by pixel equality. The protocol
  /// form of `Snapshotting<NSViewController, NSImage>.image`.
  ///
  /// A dedicated struct rather than a pullback of `NSViewImageStrategy`: a pullback transform
  /// would have to `sending`-return `viewController.view`, which aliases the controller it came
  /// from. Calling the plain-parameter render helper from a `@MainActor` witness sidesteps that.
  public struct NSViewControllerImageStrategy: SnapshotStrategy {
    public typealias Value = NSViewController
    public typealias Format = NSImage

    let precision: Float
    let perceptualPrecision: Float
    let size: CGSize?

    public init(precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize? = nil) {
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
      self.size = size
    }

    public var pathExtension: String? { "png" }
    public var diffing: NSImageDiffing {
      NSImageDiffing(precision: precision, perceptualPrecision: perceptualPrecision)
    }

    @MainActor
    public func snapshot(of viewController: sending NSViewController) async -> sending NSImage {
      await renderImage(of: viewController.view, size: size)
    }
  }

  extension SnapshotStrategy where Self == NSViewControllerImageStrategy {
    /// A snapshot strategy for comparing view controller views based on pixel equality.
    public static var image: NSViewControllerImageStrategy { NSViewControllerImageStrategy() }

    /// A snapshot strategy for comparing view controller views based on pixel equality, with
    /// configurable precision and an optional size override.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize? = nil
    ) -> NSViewControllerImageStrategy {
      NSViewControllerImageStrategy(
        precision: precision, perceptualPrecision: perceptualPrecision, size: size)
    }
  }

  extension SnapshotStrategy where Self == _Pullback<NSViewController, LinesStrategy> {
    /// A snapshot strategy for comparing view controller views based on a recursive description of
    /// their properties and hierarchies.
    public static var recursiveDescription: _Pullback<NSViewController, LinesStrategy> {
      LinesStrategy().pullback { (viewController: NSViewController) -> String in
        subtreeDescription(of: viewController.view)
      }
    }
  }
#endif
