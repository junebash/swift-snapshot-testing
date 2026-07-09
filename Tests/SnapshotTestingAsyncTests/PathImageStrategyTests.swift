#if os(macOS)
  import Cocoa
  import Testing

  @testable import SnapshotTestingAsync

  /// Coverage for the macOS `CALayer`/`CGPath`/`NSBezierPath` `.image` strategies.
  ///
  /// These are *not* byte-identity tests against the legacy references: `testCALayer` is iOS-only
  /// (no macOS reference exists) and the legacy `testCGPath`/`testNSBezierPath` image assertions are
  /// gated behind `!GITHUB_WORKFLOW` precisely because that rendering is machine-dependent. So these
  /// are self-consistency + real-difference smoke tests: they prove each strategy compiles, renders a
  /// non-empty image, renders *deterministically* (a re-render matches), and that the shared
  /// `NSImageStrategy` diffing actually detects a changed input. Byte-identity for `CALayer`/`CGPath`
  /// is deferred to the iOS-simulator canary, where real references exist.
  @Suite @MainActor struct PathImageStrategyTests {
    // Local path/layer builders — deliberately NOT `extension CGPath { static var heart }`, to avoid
    // a same-target redeclaration collision with any heart helper other test files define.

    private func makeBorderedLayer() -> CALayer {
      let layer = CALayer()
      layer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
      layer.backgroundColor = NSColor.red.cgColor
      layer.borderWidth = 4
      layer.borderColor = NSColor.black.cgColor
      return layer
    }

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
      path.addEllipse(
        in: CGRect(x: 2 * scale, y: 2 * scale, width: scale, height: scale))
      return path
    }

    private func makeHeartNSBezierPath() -> NSBezierPath {
      let scale: CGFloat = 30
      let path = NSBezierPath()
      path.move(to: CGPoint(x: 0, y: 0))
      path.line(to: CGPoint(x: 0, y: 2 * scale))
      path.curve(
        to: CGPoint(x: scale, y: 3 * scale), controlPoint1: CGPoint(x: 0, y: 2.5 * scale),
        controlPoint2: CGPoint(x: 0.5 * scale, y: 3 * scale))
      path.curve(
        to: CGPoint(x: 2 * scale, y: 2 * scale),
        controlPoint1: CGPoint(x: 1.5 * scale, y: 3 * scale),
        controlPoint2: CGPoint(x: 2 * scale, y: 2.5 * scale))
      path.curve(
        to: CGPoint(x: 3 * scale, y: scale), controlPoint1: CGPoint(x: 2.5 * scale, y: 2 * scale),
        controlPoint2: CGPoint(x: 3 * scale, y: 1.5 * scale))
      path.curve(
        to: CGPoint(x: 2 * scale, y: 0), controlPoint1: CGPoint(x: 3 * scale, y: 0.5 * scale),
        controlPoint2: CGPoint(x: 2.5 * scale, y: 0))
      path.line(to: CGPoint(x: 0, y: 0))
      path.close()
      path.appendOval(in: CGRect(x: 2 * scale, y: 2 * scale, width: scale, height: scale))
      return path
    }

    @Test func layerImageRendersNonEmptyAndDeterministically() async throws {
      let reference = await _recordSnapshot(of: makeBorderedLayer(), as: .image)
      #expect(!reference.isEmpty)
      let rerendered = try await _verifySnapshot(
        of: makeBorderedLayer(), as: .image, reference: reference)
      #expect(rerendered == nil)
    }

    @Test func layerImageDiffingDetectsChangedInput() async throws {
      let reference = await _recordSnapshot(of: makeBorderedLayer(), as: .image)
      let borderless = makeBorderedLayer()
      borderless.borderWidth = 0
      let diff = try await _verifySnapshot(of: borderless, as: .image, reference: reference)
      #expect(diff != nil)
    }

    @Test func cgPathImageRendersNonEmptyAndDeterministically() async throws {
      let reference = await _recordSnapshot(of: makeHeartCGPath(), as: .image)
      #expect(!reference.isEmpty)
      let rerendered = try await _verifySnapshot(
        of: makeHeartCGPath(), as: .image, reference: reference)
      #expect(rerendered == nil)
    }

    @Test func nsBezierPathImageRendersNonEmptyAndDeterministically() async throws {
      let reference = await _recordSnapshot(of: makeHeartNSBezierPath(), as: .image)
      #expect(!reference.isEmpty)
      let rerendered = try await _verifySnapshot(
        of: makeHeartNSBezierPath(), as: .image, reference: reference)
      #expect(rerendered == nil)
    }
  }
#endif
