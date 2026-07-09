#if canImport(SwiftUI) && (os(iOS) || os(tvOS))
  import SwiftUI
  import UIKit

  /// The size constraint for a snapshot (similar to `PreviewLayout`).
  public enum SwiftUISnapshotLayout: Sendable {
    /// Center the view in a device container described by `config`.
    case device(config: ViewImageConfig)
    /// Center the view in a fixed size container.
    case fixed(width: CGFloat, height: CGFloat)
    /// Fit the view to the ideal size that fits its content.
    case sizeThatFits
  }

  /// Renders a SwiftUI view to an image (via a `UIHostingController`) and compares by pixel
  /// equality. The protocol form of `Snapshotting<SwiftUI.View, UIImage>.image`.
  public struct SwiftUIViewImageStrategy<Value: SwiftUI.View>: SnapshotStrategy {
    public typealias Format = UIImage

    let drawHierarchyInKeyWindow: Bool
    let precision: Float
    let perceptualPrecision: Float
    let layout: SwiftUISnapshotLayout
    let traits: UITraitCollection

    public init(
      drawHierarchyInKeyWindow: Bool = false,
      precision: Float = 1,
      perceptualPrecision: Float = 1,
      layout: SwiftUISnapshotLayout = .sizeThatFits,
      traits: UITraitCollection = .init()
    ) {
      self.drawHierarchyInKeyWindow = drawHierarchyInKeyWindow
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
      self.layout = layout
      self.traits = traits
    }

    public var pathExtension: String? { "png" }
    public var diffing: UIImageDiffing {
      UIImageDiffing(
        precision: precision, perceptualPrecision: perceptualPrecision,
        scale: traits.displayScale)
    }

    @MainActor
    public func snapshot(of view: sending Value) async -> sending UIImage {
      var config: ViewImageConfig
      switch layout {
      case let .device(config: deviceConfig):
        config = deviceConfig
      case .sizeThatFits:
        config = .init(safeArea: .zero, size: nil, traits: traits)
      case let .fixed(width: width, height: height):
        config = .init(safeArea: .zero, size: CGSize(width: width, height: height), traits: traits)
      }

      let controller: UIViewController
      if config.size != nil {
        controller = UIHostingController(rootView: view)
      } else {
        let hostingController = UIHostingController(rootView: view)
        config.size = hostingController.sizeThatFits(in: CGSize(width: 0.0, height: 0.0))
        controller = hostingController
      }

      return await snapshotView(
        config: config,
        drawHierarchyInKeyWindow: drawHierarchyInKeyWindow,
        traits: traits,
        view: controller.view,
        viewController: controller
      )
    }
  }

  extension SnapshotStrategy {
    /// A snapshot strategy for comparing SwiftUI views based on pixel equality.
    ///
    /// - Parameters:
    ///   - drawHierarchyInKeyWindow: Utilize the simulator's key window in order to render
    ///     `UIAppearance` and `UIVisualEffect`s. This option requires a host application for your
    ///     tests and will _not_ work for framework test targets.
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered
    ///     a match.
    ///   - layout: A view layout override.
    ///   - traits: A trait collection override.
    public static func image<Value: SwiftUI.View>(
      drawHierarchyInKeyWindow: Bool = false,
      precision: Float = 1,
      perceptualPrecision: Float = 1,
      layout: SwiftUISnapshotLayout = .sizeThatFits,
      traits: UITraitCollection = .init()
    ) -> SwiftUIViewImageStrategy<Value>
    where Self == SwiftUIViewImageStrategy<Value> {
      SwiftUIViewImageStrategy(
        drawHierarchyInKeyWindow: drawHierarchyInKeyWindow,
        precision: precision,
        perceptualPrecision: perceptualPrecision,
        layout: layout,
        traits: traits
      )
    }
  }
#endif
