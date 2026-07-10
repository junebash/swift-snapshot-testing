import Foundation
import XCTest

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

#if canImport(Testing)
  import Testing
#endif

#if canImport(QuartzCore)
  import QuartzCore
#endif

// The public assertion layer: the async, protocol-based port of the legacy `AssertSnapshot.swift`.
//
// Everything is `@MainActor` and `async`. Because most strategies are `@MainActor` witnesses of
// the `nonisolated(nonsending)` requirement, the capture's synchronous prefix runs eagerly in the
// caller's run-loop turn — no queued main-actor work can mutate the value first — and only
// genuinely-asynchronous captures (web views) suspend. There is no synchronous overload: the old
// one blocked the main thread and spun the run loop, which is exactly the hazard the rewrite
// removes.
//
// On-disk layout, file naming, record modes, and failure messages are ported byte-for-byte so
// existing `__Snapshots__` references keep working.

/// Asserts that a given value matches a reference on disk.
///
/// - Parameters:
///   - value: A value to compare against a reference.
///   - strategy: A strategy for serializing, deserializing, and comparing values.
///   - name: An optional description of the snapshot.
///   - record: The record mode to use while asserting snapshots.
///   - snapshotDirectory: Optional directory to save snapshots. By default snapshots will be
///     saved in a directory with the same name as the test file, and that directory will sit
///     inside a directory `__Snapshots__` that sits next to your test file.
///   - timeout: The amount of time an asynchronously produced snapshot must be generated in.
///   - fileID: The file ID in which failure occurred.
///   - filePath: The file in which failure occurred.
///   - testName: The name of the test in which failure occurred.
///   - line: The line number on which failure occurred.
///   - column: The column on which failure occurred.
@MainActor
public func assertSnapshot<S: SnapshotStrategy>(
  of value: @autoclosure () throws -> S.Value,
  as strategy: S,
  named name: String? = nil,
  record: SnapshotTestingConfiguration.Record? = nil,
  snapshotDirectory: String? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async {
  let failure = await verifySnapshot(
    of: try value(),
    as: strategy,
    named: name,
    record: record,
    snapshotDirectory: snapshotDirectory,
    timeout: timeout,
    fileID: fileID,
    file: filePath,
    testName: testName,
    line: line,
    column: column
  )
  guard let message = failure else { return }
  recordIssue(
    message,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

/// Asserts that a given value matches references on disk, one per named strategy.
@MainActor
public func assertSnapshots<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as strategies: [String: any SnapshotStrategy<Value, Format>],
  record: SnapshotTestingConfiguration.Record? = nil,
  snapshotDirectory: String? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async {
  for (name, strategy) in strategies {
    await assertSnapshot(
      of: try value(),
      as: strategy,
      named: name,
      record: record,
      snapshotDirectory: snapshotDirectory,
      timeout: timeout,
      fileID: fileID,
      file: filePath,
      testName: testName,
      line: line,
      column: column
    )
  }
}

/// Asserts that a given value matches references on disk, one per strategy.
@MainActor
public func assertSnapshots<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as strategies: [any SnapshotStrategy<Value, Format>],
  record: SnapshotTestingConfiguration.Record? = nil,
  snapshotDirectory: String? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async {
  for strategy in strategies {
    await assertSnapshot(
      of: try value(),
      as: strategy,
      record: record,
      snapshotDirectory: snapshotDirectory,
      timeout: timeout,
      fileID: fileID,
      file: filePath,
      testName: testName,
      line: line,
      column: column
    )
  }
}

/// Verifies that a given value matches a reference on disk, returning a failure message when it
/// does not (and `nil` when it does).
///
/// Third party snapshot assert helpers can be built on top of this function. Simply invoke it
/// with your own arguments, and then invoke `recordIssue` (or `XCTFail`/`Issue.record`) with the
/// returned message if it is non-`nil`.
@MainActor
public func verifySnapshot<S: SnapshotStrategy>(
  of value: @autoclosure () throws -> S.Value,
  as strategy: S,
  named name: String? = nil,
  record: SnapshotTestingConfiguration.Record? = nil,
  snapshotDirectory: String? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async -> String? {
  #if canImport(Testing)
    if Test.current == nil {
      CleanCounterBetweenTestCases.registerIfNeeded()
    }
  #else
    CleanCounterBetweenTestCases.registerIfNeeded()
  #endif

  let record = record ?? SnapshotTestingConfiguration.current?.record ?? defaultRecordMode

  return await withSnapshotTesting(record: record) { () async -> String? in
    do {
      let paths = try snapshotFilePaths(
        named: name,
        snapshotDirectory: snapshotDirectory,
        pathExtension: strategy.pathExtension,
        filePath: filePath,
        testName: testName
      )

      // The capture runs directly on the caller's (main) actor so its synchronous prefix is
      // eager. The timeout can therefore only be enforced at genuine suspension points; the
      // render engines read it from this task-local context and give up (setting the flag)
      // when an asynchronous capture outlives it.
      let capture = SnapshotCaptureContext(timeout: timeout)
      let diffable = try await SnapshotCaptureContext.$current.withValue(capture) {
        await strategy.snapshot(of: try value())
      }
      if capture.timedOut {
        return timeoutFailureMessage(timeout: timeout)
      }

      var failure = try compareSnapshot(
        of: diffable,
        as: strategy,
        named: name,
        record: record,
        paths: paths,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      if failure == nil {
        failure = await settledSnapshotFailure(
          after: diffable, as: strategy, value: value, timeout: timeout)
      }
      return failure
    } catch {
      return error.localizedDescription
    }
  }
}

// MARK: - Capture context

/// Task-local context for a single snapshot capture: the assertion's timeout, and a flag the
/// render engines set when an asynchronous capture (e.g. a web view snapshot) exceeds it.
///
/// `@unchecked Sendable` is sound: the flag is guarded by a lock and the timeout is immutable.
package final class SnapshotCaptureContext: @unchecked Sendable {
  @TaskLocal package static var current: SnapshotCaptureContext?

  package let timeout: TimeInterval
  private let lock = NSLock()
  private var _timedOut = false

  package init(timeout: TimeInterval) {
    self.timeout = timeout
  }

  package var timedOut: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _timedOut
  }

  package func markTimedOut() {
    lock.lock()
    defer { lock.unlock() }
    _timedOut = true
  }
}

// MARK: - Settled-value check

/// Whether every snapshot assertion should verify that the asserted-on value was settled.
///
/// Set the `SNAPSHOT_TESTING_REQUIRE_SETTLED` environment variable to `1` to opt in: after an
/// assertion passes, the value is captured a second time following one CoreAnimation commit, and
/// the assertion fails if the two captures differ. A difference means the value was still
/// mutating when it was asserted on — pending main-queue work, in-flight animations or timers,
/// or asynchronous rendering — so the passing snapshot was a picture of an unsettled
/// intermediate state.
private var requireSettledSnapshots: Bool {
  requireSettledSnapshotsOverride
    ?? (ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_REQUIRE_SETTLED"] == "1")
}

/// Test hook: overrides the `SNAPSHOT_TESTING_REQUIRE_SETTLED` environment variable.
nonisolated(unsafe) var requireSettledSnapshotsOverride: Bool?

/// Re-captures an already-asserted value after one CoreAnimation commit and returns a failure
/// message if the second capture differs from the first, or `nil` if the value was settled.
///
/// Returns `nil` without checking when ``requireSettledSnapshots`` is off or when the second
/// capture times out — a timeout is reported by the primary assertion, not this check.
@MainActor
private func settledSnapshotFailure<S: SnapshotStrategy>(
  after first: S.Format,
  as strategy: S,
  value: () throws -> S.Value,
  timeout: TimeInterval
) async -> String? {
  guard requireSettledSnapshots else { return nil }

  await waitForOneCommit()

  let capture = SnapshotCaptureContext(timeout: timeout)
  guard
    let second = try? await SnapshotCaptureContext.$current.withValue(capture, operation: {
      await strategy.snapshot(of: try value())
    }),
    !capture.timedOut
  else { return nil }
  guard let difference = strategy.diffing.diff(first, second) else { return nil }
  return """
    Value was not settled at assertion time: capturing it again after one CoreAnimation commit \
    produced a different snapshot. Drive the value to a settled, deterministic state before \
    asserting on it — pending main-queue work, in-flight animations or timers, and asynchronous \
    rendering all mean the assertion is a picture of an intermediate state.

    \(difference.message)
    """
}

/// Suspends until the main run loop has turned and one CoreAnimation commit has completed.
@MainActor
private func waitForOneCommit() async {
  #if canImport(QuartzCore) && !os(watchOS)
    await withCheckedContinuation { continuation in
      CATransaction.begin()
      CATransaction.setCompletionBlock { continuation.resume() }
      CATransaction.commit()
    }
  #else
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  #endif
}

private func timeoutFailureMessage(timeout: TimeInterval) -> String {
  """
  Exceeded timeout of \(timeout) seconds waiting for snapshot.

  This can happen when an asynchronously rendered view (like a web view) has not loaded. \
  Ensure that every subview of the view hierarchy has loaded to avoid timeouts, or, if a \
  timeout is unavoidable, consider setting the "timeout" parameter of "assertSnapshot" to \
  a higher value.
  """
}

// MARK: - File paths

/// The on-disk locations associated with a single snapshot assertion.
private struct SnapshotFilePaths {
  let fileName: String
  let testName: String
  let snapshotFileUrl: URL
}

private func snapshotFilePaths(
  named name: String?,
  snapshotDirectory: String?,
  pathExtension: String?,
  filePath: StaticString,
  testName: String
) throws -> SnapshotFilePaths {
  let fileUrl = URL(fileURLWithPath: "\(filePath)", isDirectory: false)
  let fileName = fileUrl.deletingPathExtension().lastPathComponent

  #if os(Android)
    // When running tests on Android, the CI script copies Tests/SnapshotTestingTests/__Snapshots__
    // up to the temporary folder.
    let snapshotsBaseUrl = URL(
      fileURLWithPath: "/data/local/tmp/android-xctest",
      isDirectory: true
    )
  #else
    let snapshotsBaseUrl = fileUrl.deletingLastPathComponent()
  #endif

  let snapshotDirectoryUrl =
    snapshotDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? snapshotsBaseUrl.appendingPathComponent("__Snapshots__").appendingPathComponent(fileName)

  let identifier: String
  if let name = name {
    identifier = sanitizePathComponent(name)
  } else {
    identifier = String(
      counter.next(for: snapshotDirectoryUrl.appendingPathComponent(testName).absoluteString)
    )
  }

  let testName = sanitizePathComponent(testName)
  var snapshotFileUrl =
    snapshotDirectoryUrl
    .appendingPathComponent("\(testName).\(identifier)")
  if let ext = pathExtension {
    snapshotFileUrl = snapshotFileUrl.appendingPathExtension(ext)
  }
  try FileManager.default.createDirectory(
    at: snapshotDirectoryUrl,
    withIntermediateDirectories: true
  )

  return SnapshotFilePaths(
    fileName: fileName,
    testName: testName,
    snapshotFileUrl: snapshotFileUrl
  )
}

func sanitizePathComponent(_ string: String) -> String {
  string
    .replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
    .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
}

// MARK: - Compare

/// Compares a snapshotted value against the reference on disk, recording a new reference when
/// the record mode calls for it.
///
/// This must be called within a `withSnapshotTesting` scope.
@MainActor
private func compareSnapshot<S: SnapshotStrategy>(
  of diffable: S.Format,
  as strategy: S,
  named name: String?,
  record: SnapshotTestingConfiguration.Record,
  paths: SnapshotFilePaths,
  fileID: StaticString,
  filePath: StaticString,
  line: UInt,
  column: UInt
) throws -> String? {
  var diffable = diffable
  let fileName = paths.fileName
  let testName = paths.testName
  let snapshotFileUrl = paths.snapshotFileUrl
  let fileManager = FileManager.default

  // Hoisted so the XCTest activity closure below captures a Sendable String? instead of the
  // (not necessarily Sendable) strategy.
  let pathExtension = strategy.pathExtension

  func recordSnapshot(writeToDisk: Bool) throws {
    let snapshotData = strategy.diffing.data(from: diffable)

    if writeToDisk {
      try snapshotData.write(to: snapshotFileUrl)
    }

    #if !os(Android) && !os(Linux) && !os(Windows)
      if ProcessInfo.processInfo.environment.keys.contains("__XCODE_BUILT_PRODUCTS_DIR_PATHS") {
        if isSwiftTesting {
          #if canImport(Testing)
            recordSwiftTestingAttachment(
              writeToDisk ? try Data(contentsOf: snapshotFileUrl) : snapshotData,
              named: snapshotFileUrl.lastPathComponent,
              sourceLocation: SourceLocation(
                fileID: fileID.description,
                filePath: filePath.description,
                line: Int(line),
                column: Int(column)
              )
            )
          #endif
        } else {
          XCTContext.runActivity(named: "Attached Recorded Snapshot") { activity in
            if writeToDisk {
              let attachment = XCTAttachment(contentsOfFile: snapshotFileUrl)
              activity.add(attachment)
            } else {
              let typeIdentifier = pathExtension.flatMap(
                uniformTypeIdentifier(fromExtension:)
              )
              let attachment = XCTAttachment(
                uniformTypeIdentifier: typeIdentifier,
                name: snapshotFileUrl.lastPathComponent,
                payload: snapshotData
              )
              activity.add(attachment)
            }
          }
        }
      }
    #endif
  }

  if record == .all {
    try recordSnapshot(writeToDisk: true)

    return """
      Record mode is on. Automatically recorded snapshot: …

      open "\(snapshotFileUrl.absoluteString)"

      Turn record mode off and re-run "\(testName)" to assert against the newly-recorded snapshot
      """
  }

  guard fileManager.fileExists(atPath: snapshotFileUrl.path) else {
    if record == .never {
      try recordSnapshot(writeToDisk: false)

      return """
        No reference was found on disk. New snapshot was not recorded because recording is disabled
        """
    } else {
      try recordSnapshot(writeToDisk: true)

      return """
        No reference was found on disk. Automatically recorded snapshot: …

        open "\(snapshotFileUrl.absoluteString)"

        Re-run "\(testName)" to assert against the newly-recorded snapshot.
        """
    }
  }

  let data = try Data(contentsOf: snapshotFileUrl)
  let reference = try strategy.diffing.value(from: data)

  #if os(iOS) || os(tvOS)
    // If the image generation fails for the diffable part and the reference was empty, use the
    // reference.
    if let localDiff = diffable as? UIImage,
      let refImage = reference as? UIImage,
      localDiff.size == .zero && refImage.size == .zero
    {
      diffable = reference
    }
  #endif

  guard let difference = strategy.diffing.diff(reference, diffable) else {
    return nil
  }

  let artifactsUrl = URL(
    fileURLWithPath: ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"]
      ?? NSTemporaryDirectory(),
    isDirectory: true
  )
  let artifactsSubUrl = artifactsUrl.appendingPathComponent(fileName)
  try fileManager.createDirectory(at: artifactsSubUrl, withIntermediateDirectories: true)
  let failedSnapshotFileUrl = artifactsSubUrl.appendingPathComponent(
    snapshotFileUrl.lastPathComponent
  )
  try strategy.diffing.data(from: diffable).write(to: failedSnapshotFileUrl)

  if !difference.attachments.isEmpty {
    #if !os(Linux) && !os(Android) && !os(Windows)
      if ProcessInfo.processInfo.environment.keys.contains("__XCODE_BUILT_PRODUCTS_DIR_PATHS") {
        if isSwiftTesting {
          #if canImport(Testing)
            for attachment in difference.attachments {
              recordSwiftTestingAttachment(
                attachment.data,
                named: attachment.name ?? "attachment",
                sourceLocation: SourceLocation(
                  fileID: fileID.description,
                  filePath: filePath.description,
                  line: Int(line),
                  column: Int(column)
                )
              )
            }
          #endif
        } else {
          XCTContext.runActivity(named: "Attached Failure Diff") { activity in
            for attachment in difference.attachments {
              let xcAttachment = XCTAttachment(data: attachment.data)
              xcAttachment.name = attachment.name
              activity.add(xcAttachment)
            }
          }
        }
      }
    #endif
  }

  let diffMessage = (SnapshotTestingConfiguration.current?.diffTool ?? defaultDiffTool)(
    currentFilePath: snapshotFileUrl.path,
    failedFilePath: failedSnapshotFileUrl.path
  )

  var failureMessage: String
  if let name = name {
    failureMessage = "Snapshot \"\(name)\" does not match reference."
  } else {
    failureMessage = "Snapshot does not match reference."
  }

  if record == .failed {
    try recordSnapshot(writeToDisk: true)
    failureMessage += " A new snapshot was automatically recorded."
  }

  return """
    \(failureMessage)

    \(diffMessage)

    \(difference.message.trimmingCharacters(in: .whitespacesAndNewlines))
    """
}

// MARK: - Counter

private var counter: File.Counter {
  #if canImport(Testing)
    if Test.current != nil {
      return File.counter
    } else {
      return _counter
    }
  #else
    return _counter
  #endif
}

private let _counter = File.Counter()

enum File {
  @TaskLocal static var counter = Counter()

  final class Counter: @unchecked Sendable {
    private var counts: [String: Int] = [:]
    private let lock = NSLock()

    init() {}

    func next(for key: String) -> Int {
      lock.lock()
      defer { lock.unlock() }
      counts[key, default: 0] += 1
      return counts[key, default: 1]
    }

    func reset() {
      lock.lock()
      defer { lock.unlock() }
      counts.removeAll()
    }
  }
}

/// We need to clean the counter between test executions in order to support test iterations.
private final class CleanCounterBetweenTestCases: NSObject, XCTestObservation {
  private nonisolated(unsafe) static var registered = false

  static func registerIfNeeded() {
    guard !registered else { return }
    defer { registered = true }
    if Thread.isMainThread {
      XCTestObservationCenter.shared.addTestObserver(CleanCounterBetweenTestCases())
    } else {
      DispatchQueue.main.sync {
        XCTestObservationCenter.shared.addTestObserver(CleanCounterBetweenTestCases())
      }
    }
  }

  func testCaseDidFinish(_ testCase: XCTestCase) {
    _counter.reset()
  }
}

// MARK: - Attachments

#if !os(Android) && !os(Linux) && !os(Windows)
  import UniformTypeIdentifiers

  func uniformTypeIdentifier(fromExtension pathExtension: String) -> String? {
    UTType(filenameExtension: pathExtension)?.identifier
  }
#endif

#if canImport(Testing)
  private func recordSwiftTestingAttachment(
    _ data: Data,
    named name: String,
    sourceLocation: SourceLocation
  ) {
    #if !os(Android) && !os(Linux) && !os(Windows)
      #if compiler(>=6.3) && canImport(UIKit)
        if name.hasSuffix(".png"), let image = UIImage(data: data) {
          Attachment.record(image, named: name, as: .png, sourceLocation: sourceLocation)
          return
        }
      #elseif compiler(>=6.3) && canImport(AppKit)
        if name.hasSuffix(".png"), let image = NSImage(data: data) {
          Attachment.record(image, named: name, as: .png, sourceLocation: sourceLocation)
          return
        }
      #endif
      Attachment.record(data, named: name, sourceLocation: sourceLocation)
    #endif
  }
#endif
