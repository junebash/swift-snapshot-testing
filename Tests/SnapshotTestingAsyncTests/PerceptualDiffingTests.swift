#if os(macOS)
  import Cocoa
  import Testing

  @testable import SnapshotTestingAsync

  /// Coverage for the perceptual (`perceptualPrecision < 1`) comparison path in `NSImageDiffing`.
  ///
  /// These exercise `perceptuallyCompare` end-to-end through `diff(_:_:)` with solid-color images
  /// whose Lab ΔE relationships are unambiguous: near-identical reds sit well under a lenient
  /// threshold, while red vs. blue is far beyond a strict one. That keeps the assertions stable
  /// across the Metal and CPU (vImage) code paths, whichever this machine takes.
  @Suite @MainActor struct PerceptualDiffingTests {
    private func makeSolidImage(_ color: NSColor) -> NSImage {
      let size = CGSize(width: 20, height: 20)
      let image = NSImage(size: size)
      image.lockFocus()
      color.setFill()
      CGRect(origin: .zero, size: size).fill()
      image.unlockFocus()
      return image
    }

    @Test func nearIdenticalColorsPassLenientPerceptualPrecision() {
      let reference = makeSolidImage(NSColor(red: 1, green: 0, blue: 0, alpha: 1))
      let candidate = makeSolidImage(NSColor(red: 0.98, green: 0, blue: 0, alpha: 1))
      let diffing = NSImageDiffing(precision: 1, perceptualPrecision: 0.9)
      #expect(diffing.diff(reference, candidate) == nil)
    }

    @Test func distinctColorsFailStrictPerceptualPrecision() throws {
      let reference = makeSolidImage(.red)
      let candidate = makeSolidImage(.blue)
      let diffing = NSImageDiffing(precision: 1, perceptualPrecision: 0.99)
      let difference = try #require(diffing.diff(reference, candidate))
      #expect(difference.message.contains("perceptual color precision"))
    }

    @Test func perceptualPathStillShortCircuitsOnExactMatch() {
      let reference = makeSolidImage(.red)
      let candidate = makeSolidImage(.red)
      let diffing = NSImageDiffing(precision: 1, perceptualPrecision: 0.9)
      #expect(diffing.diff(reference, candidate) == nil)
    }

    /// The legacy engine compared pixel buffers in each image's own color profile, so this
    /// reference (recorded on a Studio Display, whose ICC profile is embedded in the PNG) never
    /// byte-matched a freshly drawn `NSColor.red` on any other display. Comparison is normalized
    /// to sRGB precisely so that identical colors match regardless of the recording machine.
    @Test func exactMatchIsIndependentOfEmbeddedColorProfile() throws {
      let referenceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("SnapshotTestingTests")
        .appendingPathComponent("__Snapshots__")
        .appendingPathComponent("SwiftTestingTests")
        .appendingPathComponent("testNSImage.pixel.png")
      let diffing = NSImageDiffing()
      let reference = try diffing.value(from: Data(contentsOf: referenceURL))
      let candidate = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
        NSColor.red.setFill()
        rect.fill()
        return true
      }
      #expect(diffing.diff(reference, candidate) == nil)
    }
  }
#endif
