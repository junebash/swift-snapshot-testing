import Foundation
import Testing

@testable import SnapshotTesting

private enum Direction: String, CaseIterable {
  case up, down, left, right
  var rotatedLeft: Direction {
    switch self {
    case .up: return .left
    case .down: return .right
    case .left: return .down
    case .right: return .up
    }
  }
}

@Suite @MainActor struct CaseIterableStrategyTests {
  /// The CSV reference recorded by the legacy suite's `testCaseIterable`.
  static let legacyReferenceURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // SnapshotTestingTests
    .deletingLastPathComponent()  // Tests
    .appendingPathComponent(
      "SnapshotTestingTests/__Snapshots__/SnapshotTestingTests/testCaseIterable.1.csv")

  /// Byte-identity against the legacy CSV: feeding every `Direction` through `{ $0.rotatedLeft }`
  /// and rendering each output via the `.description()` sub-witness must reproduce the recorded file
  /// exactly — proving the composed-witness `.func(into:)` path works end to end.
  @Test func mapsEveryCaseByteForByte() async throws {
    let strategy: _CaseIterableFuncStrategy<Direction, _Pullback<Direction, LinesStrategy>> =
      .func(into: .description())
    let produced = await _recordSnapshot(of: { $0.rotatedLeft }, as: strategy)
    let reference = try Data(contentsOf: Self.legacyReferenceURL)
    #expect(produced == reference)
  }

  /// The strategy records into a `.csv` file, matching legacy.
  @Test func usesCSVPathExtension() {
    let strategy: _CaseIterableFuncStrategy<Direction, _Pullback<Direction, LinesStrategy>> =
      .func(into: .description())
    #expect(strategy.pathExtension == "csv")
  }
}
