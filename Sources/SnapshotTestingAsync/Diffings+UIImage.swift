#if os(iOS) || os(tvOS)
  import Accelerate.vImage
  import CoreImage
  import UIKit

  /// Thrown when reference bytes cannot be decoded back into an image.
  ///
  /// Declared identically in `Diffings+NSImage.swift` for macOS. The two declarations never see
  /// each other — this file and that one are guarded by mutually exclusive `#if os(...)` — so
  /// duplicating this trivial type here avoids introducing a cross-platform file for a single
  /// error struct.
  public struct ImageDecodingError: Error {
    public var message: String
    public init(message: String) { self.message = message }
  }

  /// Pixel-diffing for `UIImage`. The protocol form of the old `Diffing<UIImage>.image`.
  ///
  /// The exact-match path (memcmp of decoded pixel buffers), the `precision` byte-threshold path,
  /// and the perceptual path (`perceptualPrecision < 1`, Lab ΔE via Core Image / Metal, in
  /// `PerceptualComparison.swift`) are all ported verbatim to keep behavior and PNG reference files
  /// identical to the legacy witness.
  public struct UIImageDiffing: DiffStrategy {
    public typealias Value = UIImage

    let precision: Float
    let perceptualPrecision: Float
    let scale: CGFloat

    public init(precision: Float = 1, perceptualPrecision: Float = 1, scale: CGFloat? = nil) {
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
      if let scale, scale != 0 {
        self.scale = scale
      } else {
        // Legacy behavior: an unspecified (or `0`, `UITraitCollection`'s default) scale falls back
        // to the main screen's scale. `UIScreen.main` is deprecated in favor of a scene's screen,
        // but a `DiffStrategy` has no scene to ask, so the deprecated API is kept for parity.
        self.scale = UIScreen.main.scale
      }
    }

    public func data(from value: UIImage) -> Data {
      value.pngData() ?? emptyImage().pngData() ?? Data()
    }

    public func value(from data: Data) throws -> UIImage {
      guard let image = UIImage(data: data, scale: scale) else {
        throw ImageDecodingError(message: "Reference image could not be loaded.")
      }
      return image
    }

    public func diff(_ reference: UIImage, _ candidate: UIImage) -> SnapshotDifference? {
      guard
        let message = compare(
          reference, candidate, precision: precision, perceptualPrecision: perceptualPrecision)
      else { return nil }
      // Used when the new image's size is zero: there is nothing meaningful to attach as
      // "failure.png", so the legacy witness substitutes a labeled placeholder image instead.
      let isEmptyImage = candidate.size == .zero
      let attachments = [
        SnapshotAttachment(
          name: "reference", data: data(from: reference), uniformTypeIdentifier: "public.png"),
        SnapshotAttachment(
          name: "failure", data: data(from: isEmptyImage ? emptyImage() : candidate),
          uniformTypeIdentifier: "public.png"),
        SnapshotAttachment(
          name: "difference", data: data(from: differenceImage(reference, candidate)),
          uniformTypeIdentifier: "public.png"),
      ]
      return SnapshotDifference(message: message, attachments: attachments)
    }
  }

  /// A snapshot strategy for comparing images based on pixel equality. The protocol form of
  /// `Snapshotting<UIImage, UIImage>.image`.
  public struct UIImageStrategy: SnapshotStrategy {
    public typealias Value = UIImage
    public typealias Format = UIImage

    let precision: Float
    let perceptualPrecision: Float
    let scale: CGFloat?

    public init(precision: Float = 1, perceptualPrecision: Float = 1, scale: CGFloat? = nil) {
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
      self.scale = scale
    }

    public var pathExtension: String? { "png" }
    public var diffing: UIImageDiffing {
      UIImageDiffing(precision: precision, perceptualPrecision: perceptualPrecision, scale: scale)
    }

    public func snapshot(of value: sending UIImage) -> sending UIImage { value }
  }

  extension SnapshotStrategy where Self == UIImageStrategy {
    /// A snapshot strategy for comparing images based on pixel equality.
    public static var image: UIImageStrategy { UIImageStrategy() }

    /// A snapshot strategy for comparing images with configurable precision.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, scale: CGFloat? = nil
    ) -> UIImageStrategy {
      UIImageStrategy(precision: precision, perceptualPrecision: perceptualPrecision, scale: scale)
    }
  }

  // remap snapshot & reference to same colorspace
  private let imageContextColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
  private let imageContextBitsPerComponent = 8
  private let imageContextBytesPerPixel = 4

  private func compare(_ old: UIImage, _ new: UIImage, precision: Float, perceptualPrecision: Float)
    -> String?
  {
    guard let oldCgImage = old.cgImage else {
      return "Reference image could not be loaded."
    }
    guard let newCgImage = new.cgImage else {
      return "Newly-taken snapshot could not be loaded."
    }
    guard newCgImage.width != 0, newCgImage.height != 0 else {
      return "Newly-taken snapshot is empty."
    }
    guard oldCgImage.width == newCgImage.width, oldCgImage.height == newCgImage.height else {
      return "Newly-taken snapshot@\(new.size) does not match reference@\(old.size)."
    }
    let pixelCount = oldCgImage.width * oldCgImage.height
    let byteCount = imageContextBytesPerPixel * pixelCount
    var oldBytes = [UInt8](repeating: 0, count: byteCount)
    guard let oldData = context(for: oldCgImage, data: &oldBytes)?.data else {
      return "Reference image's data could not be loaded."
    }
    if let newContext = context(for: newCgImage), let newData = newContext.data {
      if memcmp(oldData, newData, byteCount) == 0 { return nil }
    }
    var newerBytes = [UInt8](repeating: 0, count: byteCount)
    guard
      let pngData = new.pngData(),
      let newerCgImage = UIImage(data: pngData)?.cgImage,
      let newerContext = context(for: newerCgImage, data: &newerBytes),
      let newerData = newerContext.data
    else {
      return "Newly-taken snapshot's data could not be loaded."
    }
    if memcmp(oldData, newerData, byteCount) == 0 { return nil }
    if precision >= 1, perceptualPrecision >= 1 {
      return "Newly-taken snapshot does not match reference."
    }
    if perceptualPrecision < 1 {
      return perceptuallyCompare(
        CIImage(cgImage: oldCgImage),
        CIImage(cgImage: newCgImage),
        pixelPrecision: precision,
        perceptualPrecision: perceptualPrecision
      )
    }
    let byteCountThreshold = Int((1 - precision) * Float(byteCount))
    var differentByteCount = 0
    // NB: We are purposely using a verbose 'while' loop instead of a 'for in' loop.  When the
    //     compiler doesn't have optimizations enabled, like in test targets, a `while` loop is
    //     significantly faster than a `for` loop for iterating through the elements of a memory
    //     buffer. Details can be found in [SR-6983](https://github.com/apple/swift/issues/49531)
    var index = 0
    while index < byteCount {
      defer { index += 1 }
      if oldBytes[index] != newerBytes[index] {
        differentByteCount += 1
      }
    }
    if differentByteCount > byteCountThreshold {
      let actualPrecision = 1 - Float(differentByteCount) / Float(byteCount)
      return "Actual image precision \(actualPrecision) is less than required \(precision)"
    }
    return nil
  }

  private func context(for cgImage: CGImage, data: UnsafeMutableRawPointer? = nil) -> CGContext? {
    let bytesPerRow = cgImage.width * imageContextBytesPerPixel
    guard
      let colorSpace = imageContextColorSpace,
      let context = CGContext(
        data: data,
        width: cgImage.width,
        height: cgImage.height,
        bitsPerComponent: imageContextBitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    return context
  }

  private func differenceImage(_ old: UIImage, _ new: UIImage) -> UIImage {
    normalizedComponentDiff(old, new)
      ?? blendModeDiff(old, new)
  }

  private func blendModeDiff(_ old: UIImage, _ new: UIImage) -> UIImage {
    let width = max(old.size.width, new.size.width)
    let height = max(old.size.height, new.size.height)
    let scale = max(old.scale, new.scale)
    // Ported from `UIGraphicsBeginImageContextWithOptions` + a force-unwrapped
    // `UIGraphicsGetImageFromCurrentImageContext()`. `UIGraphicsImageRenderer` produces the same
    // opaque, blend-composited bitmap without a context that can fail to yield an image.
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
    return renderer.image { _ in
      new.draw(at: .zero)
      old.draw(at: .zero, blendMode: .difference, alpha: 1)
    }
  }

  private func normalizedComponentDiff(_ old: UIImage, _ new: UIImage) -> UIImage? {
    guard
      let oldCgImage = old.cgImage,
      let pngData = new.pngData(),
      let newCgImage = UIImage(data: pngData)?.cgImage,
      oldCgImage.width == newCgImage.width,
      oldCgImage.height == newCgImage.height,
      let oldData = oldCgImage.dataProvider?.data,
      let newData = newCgImage.dataProvider?.data,
      let oldBytes = CFDataGetBytePtr(oldData),
      let newBytes = CFDataGetBytePtr(newData)
    else {
      return nil
    }

    guard let outputColorSpace = CGColorSpace(name: CGColorSpace.linearGray),
          let outputFormat = vImage_CGImageFormat(
            bitsPerComponent: imageContextBitsPerComponent,
            bitsPerPixel: imageContextBitsPerComponent,
            colorSpace: outputColorSpace,
            bitmapInfo: .init()
          )
    else {
      return nil
    }

    let width = oldCgImage.width
    let height = oldCgImage.height
    let pixelCount = width * height
    let scale = old.scale

    var diffBytes = [UInt8](repeating: 0, count: pixelCount)

    var index = 0
    while index < pixelCount {
      defer { index += 1 }
      let pixelOffset = index * imageContextBytesPerPixel

      let rOld = Int16(oldBytes[pixelOffset])
      let gOld = Int16(oldBytes[pixelOffset + 1])
      let bOld = Int16(oldBytes[pixelOffset + 2])
      let aOld = Int16(oldBytes[pixelOffset + 3])

      let rNew = Int16(newBytes[pixelOffset])
      let gNew = Int16(newBytes[pixelOffset + 1])
      let bNew = Int16(newBytes[pixelOffset + 2])
      let aNew = Int16(newBytes[pixelOffset + 3])

      let rDiff = abs(rOld - rNew)
      let gDiff = abs(gOld - gNew)
      let bDiff = abs(bOld - bNew)
      let aDiff = abs(aOld - aNew)

      let maxDiff = max(rDiff, gDiff, bDiff, aDiff)
      diffBytes[index] = UInt8(maxDiff)
    }

    let outputCgImage: CGImage? = diffBytes.withUnsafeMutableBytes { diffPtr in
      var diffBuffer = vImage_Buffer(
        data: diffPtr.baseAddress,
        height: vImagePixelCount(height),
        width: vImagePixelCount(width),
        rowBytes: width
      )

      do {
        var normalizedBuffer = try vImage_Buffer(
          width: width,
          height: height,
          bitsPerPixel: UInt32(imageContextBitsPerComponent)
        )
        defer { normalizedBuffer.free() }

        let error = vImageContrastStretch_Planar8(
          &diffBuffer,
          &normalizedBuffer,
          vImage_Flags(kvImageNoFlags)
        )

        let buffer = error == kvImageNoError ? normalizedBuffer : diffBuffer

        return try buffer.createCGImage(format: outputFormat)
      } catch {
        return nil
      }
    }

    guard let outputCgImage else { return nil }

    return UIImage(cgImage: outputCgImage, scale: scale, orientation: .up)
  }

  /// Used when the image size has no width or no height, to generate the default empty image.
  ///
  /// The legacy witness built this from a `UILabel`, but `DiffStrategy` conformances must stay
  /// synchronous and off the main actor (see `DiffStrategy`'s documentation), and `UIView`
  /// subclasses are main-actor-isolated in modern SDKs. Drawing the placeholder directly with
  /// `NSAttributedString` onto a bitmap context reproduces the same visual (red background,
  /// centered, wrapped message) without instantiating a view.
  private func emptyImage() -> UIImage {
    let size = CGSize(width: 400, height: 80)
    let message =
      "Error: No image could be generated for this view as its size was zero. Please set an explicit size in the test."
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraphStyle]
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      UIColor.red.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      (message as NSString).draw(
        in: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4), withAttributes: attributes)
    }
  }
#endif
