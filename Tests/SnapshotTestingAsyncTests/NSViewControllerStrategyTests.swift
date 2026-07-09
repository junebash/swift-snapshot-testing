#if os(macOS)
  import Cocoa
  import Testing

  @testable import SnapshotTestingAsync

  /// Coverage for the `NSViewController` strategies. The controller is given the exact view from
  /// the legacy `testNSViewWithLayer`, so the references that byte-validate the `NSView` strategies
  /// validate the controller pullthrough too.
  @Suite @MainActor struct NSViewControllerStrategyTests {
    static let legacySnapshotsURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // SnapshotTestingAsyncTests
      .deletingLastPathComponent()  // Tests
      .appendingPathComponent("SnapshotTestingTests/__Snapshots__/SnapshotTestingTests")

    private func makeLayerViewController() -> NSViewController {
      let view = NSView()
      view.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.green.cgColor
      view.layer?.cornerRadius = 5
      let viewController = NSViewController()
      viewController.view = view
      return viewController
    }

    @Test func imageMatchesLegacyNSViewReferenceByteForByte() async throws {
      let reference = try Data(
        contentsOf: Self.legacySnapshotsURL.appendingPathComponent("testNSViewWithLayer.1.png"))
      let diff = try await _verifySnapshot(
        of: makeLayerViewController(), as: .image, reference: reference)
      #expect(diff == nil)
    }

    @Test func recursiveDescriptionMatchesLegacyNSViewReferenceByteForByte() async throws {
      let reference = try Data(
        contentsOf: Self.legacySnapshotsURL.appendingPathComponent("testNSViewWithLayer.2.txt"))
      let viewController = makeLayerViewController()
      // Same pre-state as RecursiveDescriptionTests: the legacy reference was recorded after an
      // image assertion had already laid the view out, clearing the L=needsLayout flag.
      viewController.view.layoutSubtreeIfNeeded()
      let diff = try await _verifySnapshot(
        of: viewController, as: .recursiveDescription, reference: reference)
      #expect(diff == nil)
    }
  }
#endif
