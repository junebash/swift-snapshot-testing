import CustomDump
import Foundation
import Testing

@testable import SnapshotTestingAsync
import SnapshotTestingCustomDump

/// Coverage for the `.customDump()` strategy. No legacy test ever exercised `.customDump`, so
/// there is no recorded reference to compare against; the strategy is a direct pullback of
/// `String(customDumping:)`, so that function is the oracle.
@Suite @MainActor struct CustomDumpStrategyTests {
  private struct User {
    let bio = "Blobbed around the world."
    let id = 1
    let name = "Blobby"
  }

  @Test func matchesCustomDumpOutput() async throws {
    let expected = String(customDumping: User())
    let diff = try await _verifySnapshot(of: User(), as: .customDump(), reference: Data(expected.utf8))
    #expect(diff == nil)
  }

  @Test func detectsDifference() async throws {
    let reference = await _recordSnapshot(of: User(), as: .customDump())
    let diff = try await _verifySnapshot(of: ["not", "a", "user"], as: .customDump(), reference: reference)
    #expect(diff != nil)
  }
}
