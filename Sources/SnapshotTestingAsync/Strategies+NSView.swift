#if os(macOS)
  import Cocoa
  import SceneKit
  import SpriteKit
  import WebKit

  // MARK: - NSImage

  /// Compares images by pixel equality. The protocol form of `Snapshotting<NSImage, NSImage>.image`.
  public struct NSImageStrategy: SnapshotStrategy {
    public typealias Value = NSImage
    public typealias Format = NSImage

    let precision: Float
    let perceptualPrecision: Float

    public init(precision: Float = 1, perceptualPrecision: Float = 1) {
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
    }

    public var pathExtension: String? { "png" }
    public var diffing: NSImageDiffing {
      NSImageDiffing(precision: precision, perceptualPrecision: perceptualPrecision)
    }

    public func snapshot(of value: sending NSImage) -> sending NSImage { value }
  }

  extension SnapshotStrategy where Self == NSImageStrategy {
    /// A snapshot strategy for comparing images based on pixel equality.
    public static var image: NSImageStrategy { NSImageStrategy() }

    /// A snapshot strategy for comparing images with configurable precision.
    public static func image(precision: Float = 1, perceptualPrecision: Float = 1)
      -> NSImageStrategy
    {
      NSImageStrategy(precision: precision, perceptualPrecision: perceptualPrecision)
    }
  }

  // MARK: - NSView

  /// Renders a view to an image and compares by pixel equality. The protocol form of
  /// `Snapshotting<NSView, NSImage>.image`.
  ///
  /// This is the async canary: a `@MainActor` witness satisfies the `nonisolated(nonsending)`
  /// requirement (the `sending` parameter lets the non-`Sendable` `NSView` cross in). Because the
  /// assertion caller is on `@MainActor`, the render runs eagerly in the caller's turn; a
  /// `WKWebView` subview is the only genuinely-async path, awaited via a checked continuation in the
  /// render engine.
  public struct NSViewImageStrategy: SnapshotStrategy {
    public typealias Value = NSView
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
    public func snapshot(of view: sending NSView) async -> sending NSImage {
      let initialSize = view.frame.size
      if let size { view.frame.size = size }
      guard view.frame.width > 0, view.frame.height > 0 else {
        fatalError("View not renderable to image at size \(view.frame.size)")
      }
      let overlays = await renderedSubviewImages(of: view)
      guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        fatalError("View could not be cached for display at size \(view.bounds.size)")
      }
      view.cacheDisplay(in: view.bounds, to: bitmapRep)
      let image = NSImage(size: view.bounds.size)
      image.addRepresentation(bitmapRep)
      overlays.forEach { $0.removeFromSuperview() }
      view.frame.size = initialSize
      return image
    }
  }

  extension SnapshotStrategy where Self == NSViewImageStrategy {
    /// A snapshot strategy for comparing views based on pixel equality.
    public static var image: NSViewImageStrategy { NSViewImageStrategy() }

    /// A snapshot strategy for comparing views based on pixel equality, with configurable precision
    /// and an optional size override.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize? = nil
    ) -> NSViewImageStrategy {
      NSViewImageStrategy(precision: precision, perceptualPrecision: perceptualPrecision, size: size)
    }
  }

  extension SnapshotStrategy where Self == _Pullback<NSView, LinesStrategy> {
    /// A snapshot strategy for comparing views based on a recursive description of their properties
    /// and hierarchies.
    ///
    /// ``` swift
    /// await assertSnapshot(of: view, as: .recursiveDescription)
    /// ```
    ///
    /// Records:
    ///
    /// ```
    /// [   AF      LU ] h=--- v=--- NSButton "Push Me" f=(0,0,77,32) b=(-)
    ///   [   A       LU ] h=--- v=--- NSButtonBezelView f=(0,0,77,32) b=(-)
    ///   [   AF      LU ] h=--- v=--- NSButtonTextField "Push Me" f=(10,6,57,16) b=(-)
    /// ```
    public static var recursiveDescription: _Pullback<NSView, LinesStrategy> {
      LinesStrategy().pullback { (view: NSView) -> String in
        // `_subtreeDescription` is AppKit's private hierarchy dump — same selector the legacy
        // witness used; it always returns an `NSString`, but a runtime surprise should degrade to
        // a diffable marker rather than trap.
        let description =
          view.perform(Selector(("_subtreeDescription"))).retain().takeUnretainedValue() as? String
        return purgePointers(description ?? "<no _subtreeDescription>")
      }
    }
  }

  // MARK: - Render engine

  private final class ScaledWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
  }

  /// Overlays freshly-rendered images for any views that can only snapshot themselves asynchronously
  /// (`SCNView`, `SKView`, `WKWebView`), returning the overlay views so the caller can remove them
  /// after caching. The protocol-free async form of the legacy `addImagesForRenderedViews`.
  @MainActor
  func renderedSubviewImages(of view: NSView) async -> [NSView] {
    if let image = await view.asyncSnapshotImage() {
      let imageView = NSImageView()
      imageView.image = image
      imageView.frame = view.frame
      view.superview?.addSubview(imageView, positioned: .above, relativeTo: view)
      return [imageView]
    } else {
      var added: [NSView] = []
      for subview in view.subviews {
        added += await renderedSubviewImages(of: subview)
      }
      return added
    }
  }

  extension NSView {
    /// Snapshots views that render off the normal `cacheDisplay` path. Returns `nil` for ordinary
    /// views (which render synchronously via `cacheDisplay`). The `WKWebView` case is the genuinely
    /// asynchronous one, bridged from its callback API with a checked continuation.
    @MainActor
    func asyncSnapshotImage() async -> NSImage? {
      func inWindow<T>(_ perform: () -> T) -> T {
        let superview = self.superview
        defer { superview?.addSubview(self) }
        let window = ScaledWindow()
        window.contentView = NSView()
        window.contentView?.addSubview(self)
        window.makeKey()
        return perform()
      }

      if let scnView = self as? SCNView {
        return inWindow { scnView.snapshot() }
      } else if let skView = self as? SKView {
        return inWindow {
          guard let scene = skView.scene, let texture = skView.texture(from: scene) else {
            return nil
          }
          return NSImage(cgImage: texture.cgImage(), size: skView.bounds.size)
        }
      } else if let wkWebView = self as? WKWebView {
        if wkWebView.isLoading {
          await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = WebViewLoadObserver(wkWebView) { continuation.resume() }
          }
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
          inWindow {
            guard wkWebView.frame.width != 0, wkWebView.frame.height != 0 else {
              continuation.resume(returning: NSImage())
              return
            }
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = false
            wkWebView.takeSnapshot(with: configuration) { image, _ in
              continuation.resume(returning: image)
            }
          }
        }
      }
      return nil
    }
  }

#endif
