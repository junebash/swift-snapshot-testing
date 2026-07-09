import Foundation
import Testing

@testable import SnapshotTesting

@Suite struct LinesStrategyTests {
  @Test @MainActor func identicalStringsMatch() async throws {
    let diff = try await _verifySnapshot(
      of: "hello\nworld", as: .lines, reference: Data("hello\nworld".utf8))
    #expect(diff == nil)
  }

  @Test @MainActor func differingStringsProducePatch() async throws {
    let diff = try await _verifySnapshot(
      of: "hello\nthere", as: .lines, reference: Data("hello\nworld".utf8))
    let difference = try #require(diff)
    #expect(difference.message.contains("world"))
    #expect(difference.message.contains("there"))
    #expect(difference.attachments.first?.name == "difference.patch")
  }
}

#if os(macOS)
  import Cocoa

  @Suite @MainActor struct NSViewCanaryTests {
    /// The reference recorded by the legacy suite's `testNSViewWithLayer`.
    static let legacyReferenceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // SnapshotTestingTests
      .deletingLastPathComponent()  // Tests
      .appendingPathComponent(
        "SnapshotTestingTests/__Snapshots__/SnapshotTestingTests/testNSViewWithLayer.1.png")

    /// Reconstructs `testNSViewWithLayer`'s exact view: a 10×10 green rounded layer-backed view.
    private func makeLayerView() -> NSView {
      let view = NSView()
      view.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.green.cgColor
      view.layer?.cornerRadius = 5
      return view
    }

    /// The heart of the canary: the ported async render engine must produce byte-identical output to
    /// the legacy renderer, validated against the reference the old suite recorded.
    @Test func matchesLegacyReferenceByteForByte() async throws {
      let reference = try Data(contentsOf: Self.legacyReferenceURL)
      let diff = try await _verifySnapshot(of: makeLayerView(), as: .image, reference: reference)
      #expect(diff == nil)
    }

    /// Determinism + the non-`Sendable` `NSImage` flowing back out through the async witness.
    @Test func captureIsDeterministic() async throws {
      let first = await NSViewImageStrategy().snapshot(of: makeLayerView())
      let reference = NSImageDiffing().data(from: first)
      let diff = try await _verifySnapshot(of: makeLayerView(), as: .image, reference: reference)
      #expect(diff == nil)
    }

    /// The diffing must actually detect a real pixel difference (green vs red).
    @Test func detectsRealDifference() async throws {
      let redView = makeLayerView()
      redView.layer?.backgroundColor = NSColor.red.cgColor
      let greenReference = await _recordSnapshot(of: makeLayerView(), as: .image)
      let diff = try await _verifySnapshot(of: redView, as: .image, reference: greenReference)
      #expect(diff != nil)
    }

  }
#endif
