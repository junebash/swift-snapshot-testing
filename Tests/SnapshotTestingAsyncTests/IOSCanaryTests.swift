#if os(iOS)
  import Testing
  import UIKit

  @testable import SnapshotTestingAsync

  /// The iOS-simulator canary: validates the ported iOS strategies against the legacy suite's
  /// recorded references before the wider UIKit fan-out.
  ///
  /// The strongest oracle here is `testUIBezierPath.iOS.txt` — a text reference immune to renderer
  /// drift across iOS versions. The `testCALayer.1.png` byte-identity test additionally validates
  /// the whole `UIImageStrategy`/`UIImageDiffing` pipeline; it was recorded at 3× scale (300×300
  /// for a 100-point layer), so it must run on a 3× device (e.g. iPhone 16 Pro). Solid colors and
  /// hairline borders make it the most version-stable of the 2020-era pixel references.
  @Suite @MainActor struct IOSCanaryTests {
    /// The directory holding the legacy suite's recorded reference files.
    static let legacySnapshotsURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // SnapshotTestingAsyncTests
      .deletingLastPathComponent()  // Tests
      .appendingPathComponent("SnapshotTestingTests/__Snapshots__/SnapshotTestingTests")

    /// Replicates `CGPath.heart` from the legacy `TestHelpers.swift`, from which
    /// `UIBezierPath.heart` (the fixture behind `testUIBezierPath`) is built.
    private func makeHeartCGPath() -> CGPath {
      let scale: CGFloat = 30
      let path = CGMutablePath()
      path.move(to: CGPoint(x: 0, y: 0))
      path.addLine(to: CGPoint(x: 0, y: 2 * scale))
      path.addQuadCurve(
        to: CGPoint(x: scale, y: 3 * scale), control: CGPoint(x: 0.125 * scale, y: 2.875 * scale))
      path.addQuadCurve(
        to: CGPoint(x: 2 * scale, y: 2 * scale),
        control: CGPoint(x: 1.875 * scale, y: 2.875 * scale))
      path.addCurve(
        to: CGPoint(x: 3 * scale, y: scale), control1: CGPoint(x: 2.5 * scale, y: 2 * scale),
        control2: CGPoint(x: 3 * scale, y: 1.5 * scale))
      path.addCurve(
        to: CGPoint(x: 2 * scale, y: 0), control1: CGPoint(x: 3 * scale, y: 0.5 * scale),
        control2: CGPoint(x: 2.5 * scale, y: 0))
      path.addLine(to: CGPoint(x: 0, y: 0))
      path.closeSubpath()
      path.addEllipse(in: CGRect(x: 2 * scale, y: 2 * scale, width: scale, height: scale))
      return path
    }

    /// Replicates the layer from the legacy `testCALayer`.
    private func makeBorderedLayer() -> CALayer {
      let layer = CALayer()
      layer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
      layer.backgroundColor = UIColor.red.cgColor
      layer.borderWidth = 4
      layer.borderColor = UIColor.black.cgColor
      return layer
    }

    @Test func uiBezierPathElementsDescriptionMatchesLegacyReferenceByteForByte() async throws {
      let reference = try Data(
        contentsOf: Self.legacySnapshotsURL.appendingPathComponent("testUIBezierPath.iOS.txt"))
      let path = UIBezierPath(cgPath: makeHeartCGPath())
      let diff = try await _verifySnapshot(of: path, as: .elementsDescription, reference: reference)
      #expect(diff == nil)
    }

    @Test func caLayerImageMatchesLegacyReferenceByteForByte() async throws {
      let reference = try Data(
        contentsOf: Self.legacySnapshotsURL.appendingPathComponent("testCALayer.1.png"))
      let diff = try await _verifySnapshot(of: makeBorderedLayer(), as: .image, reference: reference)
      #expect(diff == nil)
    }

    @Test func caLayerImageRendersNonEmptyAndDeterministically() async throws {
      let reference = await _recordSnapshot(of: makeBorderedLayer(), as: .image)
      #expect(!reference.isEmpty)
      let rerendered = try await _verifySnapshot(
        of: makeBorderedLayer(), as: .image, reference: reference)
      #expect(rerendered == nil)
    }

    @Test func caLayerImageDiffingDetectsChangedInput() async throws {
      let reference = await _recordSnapshot(of: makeBorderedLayer(), as: .image)
      let borderless = makeBorderedLayer()
      borderless.borderWidth = 0
      let diff = try await _verifySnapshot(of: borderless, as: .image, reference: reference)
      #expect(diff != nil)
    }

    @Test func uiBezierPathImageRendersNonEmptyAndDeterministically() async throws {
      let path = UIBezierPath(cgPath: makeHeartCGPath())
      let reference = await _recordSnapshot(of: path, as: .image)
      #expect(!reference.isEmpty)
      let rerendered = try await _verifySnapshot(
        of: UIBezierPath(cgPath: makeHeartCGPath()), as: .image, reference: reference)
      #expect(rerendered == nil)
    }
  }
#endif
