import Foundation
import Testing

@testable import SnapshotTestingAsync

#if os(macOS)
  import Cocoa

  /// End-to-end coverage for the public `assertSnapshot`/`verifySnapshot` API: file naming,
  /// record modes, failure messages, and the settled-value check.
  ///
  /// Serialized because the settled-check tests toggle the process-global
  /// `requireSettledSnapshotsOverride`, which would otherwise leak into tests interleaving at
  /// suspension points.
  @Suite(.serialized) @MainActor struct PublicAssertTests {
    /// The legacy suite's recorded reference directory — the naming scheme the public API must
    /// reproduce exactly for existing references to keep working.
    static let legacySnapshotsDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // SnapshotTestingAsyncTests
      .deletingLastPathComponent()  // Tests
      .appendingPathComponent("SnapshotTestingTests/__Snapshots__/SnapshotTestingTests")

    private func makeLayerView() -> NSView {
      let view = NSView()
      view.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.green.cgColor
      view.layer?.cornerRadius = 5
      return view
    }

    private func makeTemporaryDirectory() -> String {
      FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapshotTestingAsync-\(UUID().uuidString)")
        .path
    }

    /// The complete public path — file-name construction (testName + counter + extension),
    /// reference load, capture, compare — against a reference the legacy library recorded.
    @Test func verifiesLegacyReferenceThroughPublicAPI() async {
      let failure = await verifySnapshot(
        of: makeLayerView(),
        as: .image,
        snapshotDirectory: Self.legacySnapshotsDirectory.path,
        testName: "testNSViewWithLayer"
      )
      #expect(failure == nil)
    }

    @Test func missingReferenceRecordsAndReportsByDefault() async throws {
      let directory = makeTemporaryDirectory()
      let failure = await verifySnapshot(
        of: "hello\nworld", as: .lines, named: "greeting",
        snapshotDirectory: directory, testName: "roundtrip"
      )
      let message = try #require(failure)
      #expect(message.contains("No reference was found on disk"))
      let recordedURL = URL(fileURLWithPath: directory)
        .appendingPathComponent("roundtrip.greeting.txt")
      #expect(FileManager.default.fileExists(atPath: recordedURL.path))

      // The just-recorded reference now verifies clean, and a changed value produces the
      // standard mismatch message.
      let pass = await verifySnapshot(
        of: "hello\nworld", as: .lines, named: "greeting",
        snapshotDirectory: directory, testName: "roundtrip"
      )
      #expect(pass == nil)

      let mismatch = await verifySnapshot(
        of: "goodbye\nworld", as: .lines, named: "greeting",
        snapshotDirectory: directory, testName: "roundtrip"
      )
      #expect(mismatch?.contains("Snapshot \"greeting\" does not match reference.") == true)
    }

    @Test func neverRecordModeDoesNotWriteToDisk() async throws {
      let directory = makeTemporaryDirectory()
      let failure = await verifySnapshot(
        of: "hello", as: .lines, named: "x", record: .never,
        snapshotDirectory: directory, testName: "neverMode"
      )
      let message = try #require(failure)
      #expect(message.contains("recording is disabled"))
      let wouldBeURL = URL(fileURLWithPath: directory).appendingPathComponent("neverMode.x.txt")
      #expect(!FileManager.default.fileExists(atPath: wouldBeURL.path))
    }

    @Test func allRecordModeAlwaysRecords() async throws {
      let directory = makeTemporaryDirectory()
      let failure = await verifySnapshot(
        of: "hello", as: .lines, named: "x", record: .all,
        snapshotDirectory: directory, testName: "allMode"
      )
      let message = try #require(failure)
      #expect(message.contains("Record mode is on"))
      let recordedURL = URL(fileURLWithPath: directory).appendingPathComponent("allMode.x.txt")
      #expect(FileManager.default.fileExists(atPath: recordedURL.path))
    }

    /// Eager capture end-to-end: work queued on the main queue *before* the assertion must not
    /// affect the captured snapshot, because the capture's synchronous prefix runs in the
    /// caller's run-loop turn.
    @Test func captureIsEagerAgainstQueuedMainQueueWork() async {
      let directory = makeTemporaryDirectory()
      let view = makeLayerView()
      _ = await verifySnapshot(
        of: view, as: .image, named: "eager", snapshotDirectory: directory, testName: "eager")

      let mutating = makeLayerView()
      DispatchQueue.main.async { mutating.layer?.backgroundColor = NSColor.red.cgColor }
      let failure = await verifySnapshot(
        of: mutating, as: .image, named: "eager", snapshotDirectory: directory, testName: "eager")
      #expect(failure == nil)
    }

    /// The settled-value check: with `SNAPSHOT_TESTING_REQUIRE_SETTLED` on, the same
    /// queued-mutation scenario fails, because re-capturing after one CoreAnimation commit
    /// observes the mutation that was pending at assertion time.
    @Test func settledCheckDetectsPendingMutation() async throws {
      let directory = makeTemporaryDirectory()
      let view = makeLayerView()
      _ = await verifySnapshot(
        of: view, as: .image, named: "settled", snapshotDirectory: directory, testName: "settled")

      requireSettledSnapshotsOverride = true
      defer { requireSettledSnapshotsOverride = nil }

      let mutating = makeLayerView()
      DispatchQueue.main.async { mutating.layer?.backgroundColor = NSColor.red.cgColor }
      let failure = await verifySnapshot(
        of: mutating, as: .image, named: "settled", snapshotDirectory: directory,
        testName: "settled")
      let message = try #require(failure)
      #expect(message.contains("Value was not settled at assertion time"))
    }

    /// The settled check stays silent for values that really are settled.
    @Test func settledCheckPassesForSettledValue() async {
      let directory = makeTemporaryDirectory()
      _ = await verifySnapshot(
        of: makeLayerView(), as: .image, named: "quiet", snapshotDirectory: directory,
        testName: "quiet")

      requireSettledSnapshotsOverride = true
      defer { requireSettledSnapshotsOverride = nil }

      let failure = await verifySnapshot(
        of: makeLayerView(), as: .image, named: "quiet", snapshotDirectory: directory,
        testName: "quiet")
      #expect(failure == nil)
    }

    /// `assertSnapshots` with a heterogeneous strategy dictionary (distinct concrete types behind
    /// `any SnapshotStrategy`), against pre-recorded references — no issue may be recorded.
    @Test func assertSnapshotsVerifiesEachNamedStrategy() async {
      let directory = makeTemporaryDirectory()
      let request = URLRequest(url: URL(fileURLWithPath: "/tmp/x"))
      _ = await verifySnapshot(
        of: request, as: .raw, named: "raw", snapshotDirectory: directory, testName: "multi")
      _ = await verifySnapshot(
        of: request, as: .curl, named: "curl", snapshotDirectory: directory, testName: "multi")

      await assertSnapshots(
        of: request,
        as: ["raw": .raw, "curl": .curl] as [String: any SnapshotStrategy<URLRequest, String>],
        snapshotDirectory: directory,
        testName: "multi"
      )
    }
  }
#endif
