#if os(macOS)
  import AppKit
  import CoreGraphics
  import Foundation
  import Testing

  @testable import SnapshotTesting

  /// Byte-identity checks against the legacy suite's recorded references for `testCGPath` /
  /// `testNSBezierPath`. These prove the ported `.elementsDescription` strategies produce output
  /// indistinguishable from the closure-based `Snapshotting<Value, Format>` witnesses they
  /// replace — not merely output that looks plausible.
  @Suite @MainActor struct PathStrategyTests {
    /// The directory holding the legacy suite's recorded reference files.
    static let legacySnapshotsURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // SnapshotTestingTests
      .deletingLastPathComponent()  // Tests
      .appendingPathComponent("SnapshotTestingTests/__Snapshots__/SnapshotTestingTests")

    /// Replicates `CGPath.heart` from `Tests/SnapshotTestingTests/Internal/TestHelpers.swift` — an
    /// approximation of a heart at a 45º angle with a circle above, using all available element
    /// types. Cannot import the legacy test target, so this is reconstructed verbatim.
    static var heartCGPath: CGPath {
      let scale: CGFloat = 30.0
      let path = CGMutablePath()

      path.move(to: CGPoint(x: 0.0 * scale, y: 0.0 * scale))
      path.addLine(to: CGPoint(x: 0.0 * scale, y: 2.0 * scale))
      path.addQuadCurve(
        to: CGPoint(x: 1.0 * scale, y: 3.0 * scale),
        control: CGPoint(x: 0.125 * scale, y: 2.875 * scale)
      )
      path.addQuadCurve(
        to: CGPoint(x: 2.0 * scale, y: 2.0 * scale),
        control: CGPoint(x: 1.875 * scale, y: 2.875 * scale)
      )
      path.addCurve(
        to: CGPoint(x: 3.0 * scale, y: 1.0 * scale),
        control1: CGPoint(x: 2.5 * scale, y: 2.0 * scale),
        control2: CGPoint(x: 3.0 * scale, y: 1.5 * scale)
      )
      path.addCurve(
        to: CGPoint(x: 2.0 * scale, y: 0.0 * scale),
        control1: CGPoint(x: 3.0 * scale, y: 0.5 * scale),
        control2: CGPoint(x: 2.5 * scale, y: 0.0 * scale)
      )
      path.addLine(to: CGPoint(x: 0.0 * scale, y: 0.0 * scale))
      path.closeSubpath()

      path.addEllipse(
        in: CGRect(
          origin: CGPoint(x: 2.0 * scale, y: 2.0 * scale),
          size: CGSize(width: scale, height: scale)
        ))

      return path
    }

    /// Replicates `NSBezierPath.heart` from
    /// `Tests/SnapshotTestingTests/Internal/TestHelpers.swift` — an approximation of a heart at a
    /// 45º angle with a circle above, using all available element types. Cannot import the legacy
    /// test target, so this is reconstructed verbatim.
    static var heartNSBezierPath: NSBezierPath {
      let scale: CGFloat = 30.0
      let path = NSBezierPath()

      path.move(to: CGPoint(x: 0.0 * scale, y: 0.0 * scale))
      path.line(to: CGPoint(x: 0.0 * scale, y: 2.0 * scale))
      path.curve(
        to: CGPoint(x: 1.0 * scale, y: 3.0 * scale),
        controlPoint1: CGPoint(x: 0.0 * scale, y: 2.5 * scale),
        controlPoint2: CGPoint(x: 0.5 * scale, y: 3.0 * scale)
      )
      path.curve(
        to: CGPoint(x: 2.0 * scale, y: 2.0 * scale),
        controlPoint1: CGPoint(x: 1.5 * scale, y: 3.0 * scale),
        controlPoint2: CGPoint(x: 2.0 * scale, y: 2.5 * scale)
      )
      path.curve(
        to: CGPoint(x: 3.0 * scale, y: 1.0 * scale),
        controlPoint1: CGPoint(x: 2.5 * scale, y: 2.0 * scale),
        controlPoint2: CGPoint(x: 3.0 * scale, y: 1.5 * scale)
      )
      path.curve(
        to: CGPoint(x: 2.0 * scale, y: 0.0 * scale),
        controlPoint1: CGPoint(x: 3.0 * scale, y: 0.5 * scale),
        controlPoint2: CGPoint(x: 2.5 * scale, y: 0.0 * scale)
      )
      path.line(to: CGPoint(x: 0.0 * scale, y: 0.0 * scale))
      path.close()

      path.appendOval(
        in: CGRect(
          origin: CGPoint(x: 2.0 * scale, y: 2.0 * scale),
          size: CGSize(width: scale, height: scale)
        ))

      return path
    }

    private func reference(_ name: String) throws -> Data {
      try Data(contentsOf: Self.legacySnapshotsURL.appendingPathComponent(name))
    }

    @Test func cgPathElementsDescriptionMatchesLegacyReferenceByteForByte() async throws {
      let reference = try reference("testCGPath.macOS.txt")
      let recorded = await _recordSnapshot(of: Self.heartCGPath, as: .elementsDescription)
      #expect(recorded == reference)
    }

    @Test func nsBezierPathElementsDescriptionMatchesLegacyReferenceByteForByte() async throws {
      let reference = try reference("testNSBezierPath.macOS.txt")
      let recorded = await _recordSnapshot(of: Self.heartNSBezierPath, as: .elementsDescription)
      #expect(recorded == reference)
    }
  }
#endif
