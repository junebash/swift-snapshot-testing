#if os(macOS)
  import Cocoa

  /// Thrown when reference bytes cannot be decoded back into an image.
  public struct ImageDecodingError: Error {
    public var message: String
    public init(message: String) { self.message = message }
  }

  /// Pixel-diffing for `NSImage`. The protocol form of the old `Diffing<NSImage>.image`.
  ///
  /// The exact-match path (memcmp of decoded pixel buffers), the `precision` byte-threshold path,
  /// and the perceptual path (`perceptualPrecision < 1`, Lab ΔE via Core Image / Metal, in
  /// `PerceptualComparison.swift`) follow the legacy witnesses, with one deliberate fix: pixel
  /// buffers are normalized to sRGB before comparison. The legacy engine compared bytes in each
  /// image's *own* color profile, so a reference recorded on one display (with its ICC profile
  /// embedded in the PNG) could never byte-match a capture of the identical color on a machine
  /// with a different display profile.
  public struct NSImageDiffing: DiffStrategy {
    public typealias Value = NSImage

    let precision: Float
    let perceptualPrecision: Float

    public init(precision: Float = 1, perceptualPrecision: Float = 1) {
      self.precision = precision
      self.perceptualPrecision = perceptualPrecision
    }

    public func data(from value: NSImage) -> Data {
      pngRepresentation(of: value) ?? Data()
    }

    public func value(from data: Data) throws -> NSImage {
      guard let image = NSImage(data: data) else {
        throw ImageDecodingError(message: "Reference image could not be loaded.")
      }
      return image
    }

    public func diff(_ reference: NSImage, _ candidate: NSImage) -> SnapshotDifference? {
      guard
        let message = compareImages(
          reference, candidate, precision: precision, perceptualPrecision: perceptualPrecision)
      else { return nil }
      var attachments: [SnapshotAttachment] = []
      if let referenceData = pngRepresentation(of: reference) {
        attachments.append(SnapshotAttachment(name: "reference", data: referenceData, uniformTypeIdentifier: "public.png"))
      }
      if let candidateData = pngRepresentation(of: candidate) {
        attachments.append(SnapshotAttachment(name: "failure", data: candidateData, uniformTypeIdentifier: "public.png"))
      }
      if let differenceData = pngRepresentation(of: differenceImage(reference, candidate)) {
        attachments.append(SnapshotAttachment(name: "difference", data: differenceData, uniformTypeIdentifier: "public.png"))
      }
      return SnapshotDifference(message: message, attachments: attachments)
    }
  }

  func pngRepresentation(of image: NSImage) -> Data? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = image.size
    return rep.representation(using: .png, properties: [:])
  }

  private func compareImages(
    _ old: NSImage, _ new: NSImage, precision: Float, perceptualPrecision: Float
  ) -> String? {
    guard let oldCgImage = old.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return "Reference image could not be loaded."
    }
    guard let newCgImage = new.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return "Newly-taken snapshot could not be loaded."
    }
    guard newCgImage.width != 0, newCgImage.height != 0 else {
      return "Newly-taken snapshot is empty."
    }
    guard oldCgImage.width == newCgImage.width, oldCgImage.height == newCgImage.height else {
      return "Newly-taken snapshot@\(new.size) does not match reference@\(old.size)."
    }
    guard let oldContext = context(for: oldCgImage), let oldData = oldContext.data else {
      return "Reference image's data could not be loaded."
    }
    guard let newContext = context(for: newCgImage), let newData = newContext.data else {
      return "Newly-taken snapshot's data could not be loaded."
    }
    let byteCount = oldContext.height * oldContext.bytesPerRow
    if memcmp(oldData, newData, byteCount) == 0 { return nil }
    guard
      let pngData = pngRepresentation(of: new),
      let newerCgImage = NSImage(data: pngData)?.cgImage(
        forProposedRect: nil, context: nil, hints: nil),
      let newerContext = context(for: newerCgImage),
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
    let oldRep = oldData.assumingMemoryBound(to: UInt8.self)
    let newRep = newerData.assumingMemoryBound(to: UInt8.self)
    let byteCountThreshold = Int((1 - precision) * Float(byteCount))
    var differentByteCount = 0
    var index = 0
    while index < byteCount {
      defer { index += 1 }
      if oldRep[index] != newRep[index] {
        differentByteCount += 1
      }
    }
    if differentByteCount > byteCountThreshold {
      let actualPrecision = 1 - Float(differentByteCount) / Float(byteCount)
      return "Actual image precision \(actualPrecision) is less than required \(precision)"
    }
    return nil
  }

  /// Draws the image into a fixed 8-bit sRGB layout so byte comparison is independent of each
  /// image's embedded color profile and row stride.
  private func context(for cgImage: CGImage) -> CGContext? {
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: cgImage.width,
        height: cgImage.height,
        bitsPerComponent: 8,
        bytesPerRow: cgImage.width * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    return context
  }

  private func differenceImage(_ old: NSImage, _ new: NSImage) -> NSImage {
    guard
      let oldCg = old.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let newCg = new.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let differenceFilter = CIFilter(name: "CIDifferenceBlendMode")
    else {
      return NSImage(size: old.size)
    }
    differenceFilter.setValue(CIImage(cgImage: oldCg), forKey: kCIInputImageKey)
    differenceFilter.setValue(CIImage(cgImage: newCg), forKey: kCIInputBackgroundImageKey)
    let maxSize = CGSize(
      width: max(old.size.width, new.size.width),
      height: max(old.size.height, new.size.height)
    )
    guard let output = differenceFilter.outputImage else { return NSImage(size: maxSize) }
    let rep = NSCIImageRep(ciImage: output)
    let difference = NSImage(size: maxSize)
    difference.addRepresentation(rep)
    return difference
  }
#endif
