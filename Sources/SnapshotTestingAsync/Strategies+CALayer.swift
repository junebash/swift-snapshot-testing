#if os(macOS)
  import Cocoa
  import QuartzCore

  // `CALayer` is a concrete value type, so — like the other view/image strategies — `.image` is
  // exposed on a `Self ==` constrained extension whose value type disambiguates it from the
  // `NSImage`/`NSView` `.image` accessors. The layer renders synchronously into an `NSImage` via a
  // focused `CGContext`; there is no genuinely-async path here, so eager capture holds on a
  // `@MainActor` caller.
  extension SnapshotStrategy where Self == _Pullback<CALayer, NSImageStrategy> {
    /// A snapshot strategy for comparing layers based on pixel equality.
    public static var image: _Pullback<CALayer, NSImageStrategy> { .image(precision: 1) }

    /// A snapshot strategy for comparing layers based on pixel equality.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered
    ///     a match.
    public static func image(precision: Float = 1, perceptualPrecision: Float = 1)
      -> _Pullback<CALayer, NSImageStrategy>
    {
      NSImageStrategy(precision: precision, perceptualPrecision: perceptualPrecision)
        .pullback { (layer: CALayer) -> NSImage in
          let image = NSImage(size: layer.bounds.size)
          image.lockFocus()
          guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
          }
          layer.setNeedsLayout()
          layer.layoutIfNeeded()
          layer.render(in: context)
          image.unlockFocus()
          return image
        }
    }
  }
#endif
