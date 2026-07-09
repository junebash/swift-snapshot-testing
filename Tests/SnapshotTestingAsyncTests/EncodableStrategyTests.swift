import Foundation
import Testing

@testable import SnapshotTestingAsync

/// Byte-identity checks against the legacy suite's recorded references for `testEncodable`. These
/// prove the ported `.json()`/`.plist()` strategies produce output indistinguishable from the
/// closure-based `Snapshotting<Value, Format>` witnesses they replace — not merely output that
/// looks plausible.
@Suite @MainActor struct EncodableStrategyTests {
  /// The directory holding the legacy suite's recorded reference files.
  static let legacySnapshotsURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // SnapshotTestingAsyncTests
    .deletingLastPathComponent()  // Tests
    .appendingPathComponent("SnapshotTestingTests/__Snapshots__/SnapshotTestingTests")

  /// The exact input that produced `testEncodable.1.json` and `testEncodable.2.plist` in the
  /// legacy suite.
  struct User: Encodable { let id: Int, name: String, bio: String }
  static let user = User(id: 1, name: "Blobby", bio: "Blobbed around the world.")

  @Test func jsonMatchesLegacyReferenceByteForByte() async throws {
    let reference = try Data(
      contentsOf: Self.legacySnapshotsURL.appendingPathComponent("testEncodable.1.json"))
    let recorded = await _recordSnapshot(of: Self.user, as: .json())
    #expect(recorded == reference)
  }

  @Test func plistMatchesLegacyReferenceByteForByte() async throws {
    let reference = try Data(
      contentsOf: Self.legacySnapshotsURL.appendingPathComponent("testEncodable.2.plist"))
    let recorded = await _recordSnapshot(of: Self.user, as: .plist())
    #expect(recorded == reference)
  }
}
