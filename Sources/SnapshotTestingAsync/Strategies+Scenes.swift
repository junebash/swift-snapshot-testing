#if os(iOS) || os(macOS) || os(tvOS)
  import SceneKit
  import SpriteKit
  #if os(macOS)
    import Cocoa
  #else
    import UIKit
  #endif

  // SceneKit/SpriteKit strategies: each stages its scene in a fresh view of the requested size and
  // renders through the platform view engine (whose `asyncSnapshotImage` special-cases
  // `SCNView`/`SKView`). Dedicated structs rather than pullbacks for the same aliasing reason as
  // `NSViewControllerImageStrategy`: the staged view holds the scene it was derived from, so it
  // can't be `sending`-returned from a transform.
  //
  // NB: Like the legacy witnesses, output is GPU/machine-dependent — recorded references don't
  // transfer between machines, so these carry no byte-identity oracle.

  #if os(macOS)
    public typealias _SceneImageFormat = NSImage
    public typealias _SceneImageDiffing = NSImageDiffing
  #else
    public typealias _SceneImageFormat = UIImage
    public typealias _SceneImageDiffing = UIImageDiffing
  #endif

  /// Renders a SceneKit scene to an image and compares by pixel equality. The protocol form of
  /// `Snapshotting<SCNScene, Image>.image`.
  public struct SCNSceneImageStrategy: SnapshotStrategy {
    public typealias Value = SCNScene
    public typealias Format = _SceneImageFormat

    let precision: Float
    let perceptualPrecision: Float
    let size: CGSize

    public init(precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize) {
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
      self.size = size
    }

    public var pathExtension: String? { "png" }
    public var diffing: _SceneImageDiffing {
      _SceneImageDiffing(precision: precision, perceptualPrecision: perceptualPrecision)
    }

    @MainActor
    public func snapshot(of scene: sending SCNScene) async -> sending _SceneImageFormat {
      let view = SCNView(frame: .init(x: 0, y: 0, width: size.width, height: size.height))
      view.scene = scene
      #if os(macOS)
        return await renderImage(of: view, size: nil)
      #else
        return await snapshotView(
          config: .init(safeArea: .zero, size: view.frame.size, traits: .init()),
          drawHierarchyInKeyWindow: false,
          traits: .init(),
          view: view,
          viewController: .init()
        )
      #endif
    }
  }

  extension SnapshotStrategy where Self == SCNSceneImageStrategy {
    /// A snapshot strategy for comparing SceneKit scenes based on pixel equality.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered
    ///     a match.
    ///   - size: The size of the scene.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize
    ) -> SCNSceneImageStrategy {
      SCNSceneImageStrategy(
        precision: precision, perceptualPrecision: perceptualPrecision, size: size)
    }
  }

  /// Renders a SpriteKit scene to an image and compares by pixel equality. The protocol form of
  /// `Snapshotting<SKScene, Image>.image`.
  public struct SKSceneImageStrategy: SnapshotStrategy {
    public typealias Value = SKScene
    public typealias Format = _SceneImageFormat

    let precision: Float
    let perceptualPrecision: Float
    let size: CGSize

    public init(precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize) {
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
      self.size = size
    }

    public var pathExtension: String? { "png" }
    public var diffing: _SceneImageDiffing {
      _SceneImageDiffing(precision: precision, perceptualPrecision: perceptualPrecision)
    }

    @MainActor
    public func snapshot(of scene: sending SKScene) async -> sending _SceneImageFormat {
      let view = SKView(frame: .init(x: 0, y: 0, width: size.width, height: size.height))
      view.presentScene(scene)
      #if os(macOS)
        return await renderImage(of: view, size: nil)
      #else
        return await snapshotView(
          config: .init(safeArea: .zero, size: view.frame.size, traits: .init()),
          drawHierarchyInKeyWindow: false,
          traits: .init(),
          view: view,
          viewController: .init()
        )
      #endif
    }
  }

  extension SnapshotStrategy where Self == SKSceneImageStrategy {
    /// A snapshot strategy for comparing SpriteKit scenes based on pixel equality.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered
    ///     a match.
    ///   - size: The size of the scene.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize
    ) -> SKSceneImageStrategy {
      SKSceneImageStrategy(
        precision: precision, perceptualPrecision: perceptualPrecision, size: size)
    }
  }
#endif
