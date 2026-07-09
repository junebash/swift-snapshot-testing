import SnapshotTesting
import XCTest

final class RecordTests: BaseTestCase {
  var snapshotURL: URL!

  override func setUp() {
    super.setUp()

    let testName = String(
      self.name
        .split(separator: " ")
        .flatMap { String($0).split(separator: ".") }
        .last ?? ""
    )
    .prefix(while: { $0 != "]" })
    let fileURL = URL(fileURLWithPath: #filePath, isDirectory: false)
    let testClassName = fileURL.deletingPathExtension().lastPathComponent
    let testDirectory =
      fileURL
      .deletingLastPathComponent()
      .appendingPathComponent("__Snapshots__")
      .appendingPathComponent(testClassName)
    snapshotURL =
      testDirectory
      .appendingPathComponent("\(testName).1.json")
    try? FileManager.default
      .removeItem(at: snapshotURL.deletingLastPathComponent())
    try? FileManager.default
      .createDirectory(at: testDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    super.tearDown()
    try? FileManager.default
      .removeItem(at: snapshotURL.deletingLastPathComponent())
  }

  // These tests check the exact failure message `verifySnapshot` returns rather than routing
  // through `assertSnapshot` + `XCTExpectFailure`, since `XCTExpectFailure`'s `failingBlock` has
  // no async overload and `assertSnapshot` is now async.

  func testRecordNever() async {
    let failure = await withSnapshotTesting(record: .never) {
      await verifySnapshot(of: 42, as: .json())
    }
    XCTAssertEqual(
      failure,
      """
      No reference was found on disk. New snapshot was not recorded because recording is disabled
      """
    )

    XCTAssertEqual(
      FileManager.default.fileExists(atPath: snapshotURL.path),
      false
    )
  }

  func testRecordMissing() async throws {
    let failure = await withSnapshotTesting(record: .missing) {
      await verifySnapshot(of: 42, as: .json())
    }
    XCTAssertEqual(
      failure?.hasPrefix(
        """
        No reference was found on disk. Automatically recorded snapshot: …
        """),
      true
    )

    try XCTAssertEqual(
      String(decoding: Data(contentsOf: snapshotURL), as: UTF8.self),
      "42"
    )
  }

  func testRecordMissing_ExistingFile() async throws {
    try Data("999".utf8).write(to: snapshotURL)

    let failure = await withSnapshotTesting(record: .missing) {
      await verifySnapshot(of: 42, as: .json())
    }
    XCTAssertEqual(
      failure?.hasPrefix(
        """
        Snapshot does not match reference.
        """),
      true
    )

    try XCTAssertEqual(
      String(decoding: Data(contentsOf: snapshotURL), as: UTF8.self),
      "999"
    )
  }

  func testRecordAll_Fresh() async throws {
    let failure = await withSnapshotTesting(record: .all) {
      await verifySnapshot(of: 42, as: .json())
    }
    XCTAssertEqual(
      failure?.hasPrefix(
        """
        Record mode is on. Automatically recorded snapshot: …
        """),
      true
    )

    try XCTAssertEqual(
      String(decoding: Data(contentsOf: snapshotURL), as: UTF8.self),
      "42"
    )
  }

  func testRecordAll_Overwrite() async throws {
    try Data("999".utf8).write(to: snapshotURL)

    let failure = await withSnapshotTesting(record: .all) {
      await verifySnapshot(of: 42, as: .json())
    }
    XCTAssertEqual(
      failure?.hasPrefix(
        """
        Record mode is on. Automatically recorded snapshot: …
        """),
      true
    )

    try XCTAssertEqual(
      String(decoding: Data(contentsOf: snapshotURL), as: UTF8.self),
      "42"
    )
  }

  func testRecordFailed_WhenFailure() async throws {
    try Data("999".utf8).write(to: snapshotURL)

    let failure = await withSnapshotTesting(record: .failed) {
      await verifySnapshot(of: 42, as: .json())
    }
    XCTAssertEqual(
      failure?.hasPrefix(
        """
        Snapshot does not match reference. A new snapshot was automatically recorded.
        """),
      true
    )

    try XCTAssertEqual(
      String(decoding: Data(contentsOf: snapshotURL), as: UTF8.self),
      "42"
    )
  }

  func testRecordFailed_NoFailure() async throws {
    #if os(Android)
      throw XCTSkip("cannot save next to file on Android")
    #endif
    try Data("42".utf8).write(to: snapshotURL)
    let modifiedDate =
      try FileManager.default
      .attributesOfItem(atPath: snapshotURL.path)[FileAttributeKey.modificationDate] as! Date

    let failure = await withSnapshotTesting(record: .failed) {
      await verifySnapshot(of: 42, as: .json())
    }
    XCTAssertNil(failure)

    try XCTAssertEqual(
      String(decoding: Data(contentsOf: snapshotURL), as: UTF8.self),
      "42"
    )
    XCTAssertEqual(
      try FileManager.default
        .attributesOfItem(atPath: snapshotURL.path)[FileAttributeKey.modificationDate] as! Date,
      modifiedDate
    )
  }

  func testRecordFailed_MissingFile() async throws {
    let failure = await withSnapshotTesting(record: .failed) {
      await verifySnapshot(of: 42, as: .json())
    }
    XCTAssertEqual(
      failure?.hasPrefix(
        """
        No reference was found on disk. Automatically recorded snapshot: …
        """),
      true
    )

    try XCTAssertEqual(
      String(decoding: Data(contentsOf: snapshotURL), as: UTF8.self),
      "42"
    )
  }
}
