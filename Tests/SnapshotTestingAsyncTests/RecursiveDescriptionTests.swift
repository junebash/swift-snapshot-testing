#if os(macOS)
  import Cocoa
  import Testing

  @testable import SnapshotTestingAsync

  /// Coverage for the `NSView` `.recursiveDescription` strategy, validated byte-for-byte against
  /// the reference the legacy suite's `testNSViewWithLayer` recorded (the same 10×10 green
  /// layer-backed view as `NSViewCanaryTests`). `_subtreeDescription` output for this trivial
  /// hierarchy is stable across machines, unlike the pixel references gated as machine-dependent.
  @Suite @MainActor struct RecursiveDescriptionTests {
    static let legacyReferenceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // SnapshotTestingAsyncTests
      .deletingLastPathComponent()  // Tests
      .appendingPathComponent(
        "SnapshotTestingTests/__Snapshots__/SnapshotTestingTests/testNSViewWithLayer.2.txt")

    private func makeLayerView() -> NSView {
      let view = NSView()
      view.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.green.cgColor
      view.layer?.cornerRadius = 5
      return view
    }

    @Test func matchesLegacyReferenceByteForByte() async throws {
      let reference = try Data(contentsOf: Self.legacyReferenceURL)
      let view = makeLayerView()
      // The legacy test asserted `.image` on this same view instance first; that render laid the
      // view out, clearing the `L=needsLayout` flag before the description was recorded. Reproduce
      // that pre-state, since a fresh layer-backed view starts with the flag set.
      view.layoutSubtreeIfNeeded()
      let diff = try await _verifySnapshot(of: view, as: .recursiveDescription, reference: reference)
      #expect(diff == nil)
    }

    @Test func detectsHierarchyDifference() async throws {
      let reference = await _recordSnapshot(of: makeLayerView(), as: .recursiveDescription)
      let withSubview = makeLayerView()
      withSubview.addSubview(NSView(frame: CGRect(x: 0, y: 0, width: 5, height: 5)))
      let diff = try await _verifySnapshot(
        of: withSubview, as: .recursiveDescription, reference: reference)
      #expect(diff != nil)
    }
  }
#endif
