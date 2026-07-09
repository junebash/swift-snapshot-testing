#if os(macOS)
  import Cocoa

  // macOS path→image strategies. `CGPath`/`NSBezierPath` are concrete value types, so `.image` lives
  // on `Self ==` constrained extensions whose value type disambiguates it. Each renders the path
  // synchronously into a focused `NSImage`; the `.elementsDescription` text strategies for these
  // same types live in `Strategies+Paths.swift`.

  extension SnapshotStrategy where Self == _Pullback<CGPath, NSImageStrategy> {
    /// A snapshot strategy for comparing paths based on pixel equality.
    public static var image: _Pullback<CGPath, NSImageStrategy> { .image() }

    /// A snapshot strategy for comparing paths based on pixel equality.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered
    ///     a match.
    ///   - drawingMode: The drawing mode.
    public static func image(
      precision: Float = 1,
      perceptualPrecision: Float = 1,
      drawingMode: CGPathDrawingMode = .eoFill
    ) -> _Pullback<CGPath, NSImageStrategy> {
      NSImageStrategy(precision: precision, perceptualPrecision: perceptualPrecision)
        .pullback { (path: CGPath) -> NSImage in
          let bounds = path.boundingBoxOfPath
          var transform = CGAffineTransform(translationX: -bounds.origin.x, y: -bounds.origin.y)
          guard let path = path.copy(using: &transform) else { return NSImage(size: bounds.size) }

          let image = NSImage(size: bounds.size)
          image.lockFocus()
          guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
          }
          context.addPath(path)
          context.drawPath(using: drawingMode)
          image.unlockFocus()
          return image
        }
    }
  }

  extension SnapshotStrategy where Self == _Pullback<NSBezierPath, NSImageStrategy> {
    /// A snapshot strategy for comparing paths based on pixel equality.
    public static var image: _Pullback<NSBezierPath, NSImageStrategy> { .image() }

    /// A snapshot strategy for comparing paths based on pixel equality.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered
    ///     a match.
    public static func image(precision: Float = 1, perceptualPrecision: Float = 1)
      -> _Pullback<NSBezierPath, NSImageStrategy>
    {
      NSImageStrategy(precision: precision, perceptualPrecision: perceptualPrecision)
        .pullback { (path: NSBezierPath) -> NSImage in
          let bounds = path.bounds
          let transform = AffineTransform(translationByX: -bounds.origin.x, byY: -bounds.origin.y)
          path.transform(using: transform)

          let image = NSImage(size: path.bounds.size)
          image.lockFocus()
          path.fill()
          image.unlockFocus()
          return image
        }
    }
  }
#elseif os(iOS) || os(tvOS)
  import UIKit

  extension SnapshotStrategy where Self == _Pullback<UIBezierPath, UIImageStrategy> {
    /// A snapshot strategy for comparing paths based on pixel equality.
    public static var image: _Pullback<UIBezierPath, UIImageStrategy> { .image() }

    /// A snapshot strategy for comparing paths based on pixel equality.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered
    ///     a match.
    ///   - scale: The scale to use when loading the reference image from disk.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, scale: CGFloat = 1
    ) -> _Pullback<UIBezierPath, UIImageStrategy> {
      UIImageStrategy(precision: precision, perceptualPrecision: perceptualPrecision, scale: scale)
        .pullback { (path: UIBezierPath) -> UIImage in
          let format = UIGraphicsImageRendererFormat.preferred()
          format.scale = scale
          return UIGraphicsImageRenderer(bounds: path.bounds, format: format).image { _ in
            path.fill()
          }
        }
    }
  }
#endif
