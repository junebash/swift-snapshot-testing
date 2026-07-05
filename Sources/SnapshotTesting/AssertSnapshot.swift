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

/// Enhances failure messages with a command line diff tool expression that can be copied and pasted
/// into a terminal.
@available(
  *,
  deprecated,
  message:
    "Use 'withSnapshotTesting' to customize the diff tool. See the documentation for more information."
)
public var diffTool: SnapshotTestingConfiguration.DiffTool {
  get {
    _diffTool
  }
  set { _diffTool = newValue }
}

@_spi(Internals)
public var _diffTool: SnapshotTestingConfiguration.DiffTool {
  get {
    #if canImport(Testing)
      if let test = Test.current {
        for trait in test.traits.reversed() {
          if let diffTool = (trait as? _SnapshotsTestTrait)?.configuration.diffTool {
            return diffTool
          }
        }
      }
    #endif
    return __diffTool
  }
  set {
    __diffTool = newValue
  }
}

@_spi(Internals)
public var __diffTool: SnapshotTestingConfiguration.DiffTool = .default

/// Whether or not to record all new references.
@available(
  *,
  deprecated,
  message:
    "Use 'withSnapshotTesting' to customize the record mode. See the documentation for more information."
)
public var isRecording: Bool {
  get { SnapshotTestingConfiguration.current?.record ?? _record == .all }
  set { _record = newValue ? .all : .missing }
}

@_spi(Internals)
public var _record: SnapshotTestingConfiguration.Record {
  get {
    #if canImport(Testing)
      if let test = Test.current {
        for trait in test.traits.reversed() {
          if let record = (trait as? _SnapshotsTestTrait)?.configuration.record {
            return record
          }
        }
      }
    #endif
    return __record
  }
  set {
    __record = newValue
  }
}

@_spi(Internals)
public var __record: SnapshotTestingConfiguration.Record = {
  if let value = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"],
    let record = SnapshotTestingConfiguration.Record(rawValue: value)
  {
    return record
  }
  return .missing
}()

/// Asserts that a given value matches a reference on disk.
///
/// - Parameters:
///   - value: A value to compare against a reference.
///   - snapshotting: A strategy for serializing, deserializing, and comparing values.
///   - name: An optional description of the snapshot.
///   - record: The record mode to use while asserting snapshots.
///   - timeout: The amount of time a snapshot must be generated in.
///   - fileID: The file ID in which failure occurred. Defaults to the file ID of the test case in
///     which this function was called.
///   - file: The file in which failure occurred. Defaults to the file path of the test case in
///     which this function was called.
///   - testName: The name of the test in which failure occurred. Defaults to the function name of
///     the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
///   - column: The column on which failure occurred. Defaults to the column on which this function
///     was called.
public func assertSnapshot<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  record: SnapshotTestingConfiguration.Record? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  let failure = verifySnapshot(
    of: try value(),
    as: snapshotting,
    named: name,
    record: record,
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

/// Asserts that a given value matches a reference on disk, suspending while the snapshot is
/// generated instead of blocking the current thread.
///
/// This overload works just like
/// ``assertSnapshot(of:as:named:record:timeout:fileID:file:testName:line:column:)``, except it
/// uses Swift concurrency to wait for the snapshot to be generated. The synchronous version
/// blocks the calling thread and spins the run loop until the snapshot is ready, which can slow
/// down and destabilize test suites that put a lot of pressure on the main thread. This version
/// suspends instead, leaving the main thread free to make progress on the work the snapshot
/// strategy may be waiting on.
///
/// The snapshot operation is started before this function's first suspension point. A strategy
/// that produces its value synchronously (like an image snapshot of an already-rendered view)
/// therefore captures in the same run-loop iteration as the caller — exactly what the
/// synchronous overload captures — and no main-queue work, timer, or CoreAnimation commit can
/// mutate the value first. Only the wait for asynchronously produced values suspends.
///
/// The assertion runs on the main actor because most snapshot strategies (views, view
/// controllers, SwiftUI) require main-thread access to render.
///
/// - Parameters:
///   - value: A value to compare against a reference.
///   - snapshotting: A strategy for serializing, deserializing, and comparing values.
///   - name: An optional description of the snapshot.
///   - record: The record mode to use while asserting snapshots.
///   - timeout: The amount of time a snapshot must be generated in.
///   - fileID: The file ID in which failure occurred. Defaults to the file ID of the test case in
///     which this function was called.
///   - file: The file in which failure occurred. Defaults to the file path of the test case in
///     which this function was called.
///   - testName: The name of the test in which failure occurred. Defaults to the function name of
///     the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
///   - column: The column on which failure occurred. Defaults to the column on which this function
///     was called.
@MainActor
public func assertSnapshot<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  record: SnapshotTestingConfiguration.Record? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async {
  let failure = await verifySnapshot(
    of: try value(),
    as: snapshotting,
    named: name,
    record: record,
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

/// Asserts that a given value matches references on disk.
///
/// - Parameters:
///   - value: A value to compare against a reference.
///   - strategies: A dictionary of names and strategies for serializing, deserializing, and
///     comparing values.
///   - recording: The record mode to use while asserting snapshots.
///   - timeout: The amount of time a snapshot must be generated in.
///   - fileID: The file ID in which failure occurred. Defaults to the file ID of the test case in
///     which this function was called.
///   - file: The file in which failure occurred. Defaults to the file path of the test case in
///     which this function was called.
///   - testName: The name of the test in which failure occurred. Defaults to the function name of
///     the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
///   - column: The column on which failure occurred. Defaults to the column on which this function
///     was called.
public func assertSnapshots<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as strategies: [String: Snapshotting<Value, Format>],
  record: SnapshotTestingConfiguration.Record? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  try? strategies.forEach { name, strategy in
    assertSnapshot(
      of: try value(),
      as: strategy,
      named: name,
      record: record,
      timeout: timeout,
      fileID: fileID,
      file: filePath,
      testName: testName,
      line: line,
      column: column
    )
  }
}

/// Asserts that a given value matches references on disk, suspending while each snapshot is
/// generated instead of blocking the current thread.
///
/// See ``assertSnapshot(of:as:named:record:timeout:fileID:file:testName:line:column:)-async`` for
/// more information on the concurrency behavior of this overload.
///
/// Every strategy's snapshot operation is started before this function's first suspension point,
/// in ascending order of the strategies' names. Strategies that produce their value synchronously
/// (like image snapshots of already-rendered views) all capture in the same run-loop iteration as
/// the caller, so no main-queue work, timer, or CoreAnimation commit can mutate the value between
/// one strategy's capture and the next. Strategies that produce their value asynchronously run
/// concurrently rather than one after another; each result is then compared against its reference
/// in the same order the operations were started.
///
/// - Parameters:
///   - value: A value to compare against a reference.
///   - strategies: A dictionary of names and strategies for serializing, deserializing, and
///     comparing values.
///   - record: The record mode to use while asserting snapshots.
///   - timeout: The amount of time a snapshot must be generated in.
///   - fileID: The file ID in which failure occurred. Defaults to the file ID of the test case in
///     which this function was called.
///   - file: The file in which failure occurred. Defaults to the file path of the test case in
///     which this function was called.
///   - testName: The name of the test in which failure occurred. Defaults to the function name of
///     the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
///   - column: The column on which failure occurred. Defaults to the column on which this function
///     was called.
@MainActor
public func assertSnapshots<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as strategies: [String: Snapshotting<Value, Format>],
  record: SnapshotTestingConfiguration.Record? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async {
  // Start every strategy's snapshot operation before the first suspension point, so that no
  // main-queue work, timer, or CoreAnimation commit can run between one capture and the next.
  // Suspending between captures (as `await assertSnapshot` in a loop would) lets the main run
  // loop turn, and any work it performs mutates the value out from under later strategies.
  var snapshots: [(name: String, strategy: Snapshotting<Value, Format>, snapshot: EagerSnapshot<Format>)] = []
  for (name, strategy) in strategies.sorted(by: { $0.key < $1.key }) {
    guard let snapshot = try? EagerSnapshot(strategy.snapshot(value())) else { break }
    snapshots.append((name, strategy, snapshot))
  }

  for (name, strategy, snapshot) in snapshots {
    let failure = await verifySnapshot(
      eager: snapshot,
      as: strategy,
      named: name,
      record: record,
      snapshotDirectory: nil,
      timeout: timeout,
      fileID: fileID,
      filePath: filePath,
      testName: testName,
      line: line,
      column: column
    )
    guard let message = failure else { continue }
    recordIssue(
      message,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
}

/// Asserts that a given value matches references on disk.
///
/// - Parameters:
///   - value: A value to compare against a reference.
///   - strategies: An array of strategies for serializing, deserializing, and comparing values.
///   - record: The record mode to use while asserting snapshots.
///   - timeout: The amount of time a snapshot must be generated in.
///   - fileID: The file ID in which failure occurred. Defaults to the file ID of the test case in
///     which this function was called.
///   - file: The file in which failure occurred. Defaults to the file path of the test case in
///     which this function was called.
///   - testName: The name of the test in which failure occurred. Defaults to the function name of
///     the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
///   - column: The column on which failure occurred. Defaults to the column on which this function
///     was called.
public func assertSnapshots<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as strategies: [Snapshotting<Value, Format>],
  record: SnapshotTestingConfiguration.Record? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  try? strategies.forEach { strategy in
    assertSnapshot(
      of: try value(),
      as: strategy,
      record: record,
      timeout: timeout,
      fileID: fileID,
      file: filePath,
      testName: testName,
      line: line,
      column: column
    )
  }
}

/// Asserts that a given value matches references on disk, suspending while each snapshot is
/// generated instead of blocking the current thread.
///
/// See ``assertSnapshot(of:as:named:record:timeout:fileID:file:testName:line:column:)-async`` for
/// more information on the concurrency behavior of this overload.
///
/// Every strategy's snapshot operation is started before this function's first suspension point,
/// in array order. Strategies that produce their value synchronously (like image snapshots of
/// already-rendered views) all capture in the same run-loop iteration as the caller, so no
/// main-queue work, timer, or CoreAnimation commit can mutate the value between one strategy's
/// capture and the next. Strategies that produce their value asynchronously run concurrently
/// rather than one after another; each result is then compared against its reference in array
/// order.
///
/// - Parameters:
///   - value: A value to compare against a reference.
///   - strategies: An array of strategies for serializing, deserializing, and comparing values.
///   - record: The record mode to use while asserting snapshots.
///   - timeout: The amount of time a snapshot must be generated in.
///   - fileID: The file ID in which failure occurred. Defaults to the file ID of the test case in
///     which this function was called.
///   - file: The file in which failure occurred. Defaults to the file path of the test case in
///     which this function was called.
///   - testName: The name of the test in which failure occurred. Defaults to the function name of
///     the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
///   - column: The column on which failure occurred. Defaults to the column on which this function
///     was called.
@MainActor
public func assertSnapshots<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as strategies: [Snapshotting<Value, Format>],
  record: SnapshotTestingConfiguration.Record? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async {
  // Start every strategy's snapshot operation before the first suspension point, so that no
  // main-queue work, timer, or CoreAnimation commit can run between one capture and the next.
  // Suspending between captures (as `await assertSnapshot` in a loop would) lets the main run
  // loop turn, and any work it performs mutates the value out from under later strategies.
  var snapshots: [(strategy: Snapshotting<Value, Format>, snapshot: EagerSnapshot<Format>)] = []
  for strategy in strategies {
    guard let snapshot = try? EagerSnapshot(strategy.snapshot(value())) else { break }
    snapshots.append((strategy, snapshot))
  }

  for (strategy, snapshot) in snapshots {
    let failure = await verifySnapshot(
      eager: snapshot,
      as: strategy,
      named: nil,
      record: record,
      snapshotDirectory: nil,
      timeout: timeout,
      fileID: fileID,
      filePath: filePath,
      testName: testName,
      line: line,
      column: column
    )
    guard let message = failure else { continue }
    recordIssue(
      message,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
}

/// Verifies that a given value matches a reference on disk.
///
/// Third party snapshot assert helpers can be built on top of this function. Simply invoke
/// `verifySnapshot` with your own arguments, and then invoke `XCTFail` with the string returned if
/// it is non-`nil`. For example, if you want the snapshot directory to be determined by an
/// environment variable, you can create your own assert helper like so:
///
/// ```swift
/// public func myAssertSnapshot<Value, Format>(
///   of value: @autoclosure () throws -> Value,
///   as snapshotting: Snapshotting<Value, Format>,
///   named name: String? = nil,
///   record: SnapshotTestingConfiguration.Record? = nil,
///   timeout: TimeInterval = 5,
///   file: StaticString = #file,
///   testName: String = #function,
///   line: UInt = #line
///   ) {
///
///     let snapshotDirectory = ProcessInfo.processInfo.environment["SNAPSHOT_REFERENCE_DIR"]! + "/" + #file
///     let failure = verifySnapshot(
///       of: try value(),
///       as: snapshotting,
///       named: name,
///       record: record,
///       snapshotDirectory: snapshotDirectory,
///       timeout: timeout,
///       file: file,
///       testName: testName
///     )
///     guard let message = failure else { return }
///     XCTFail(message, file: file, line: line)
/// }
/// ```
///
/// - Parameters:
///   - value: A value to compare against a reference.
///   - snapshotting: A strategy for serializing, deserializing, and comparing values.
///   - name: An optional description of the snapshot.
///   - record: The record mode to use while asserting snapshots.
///   - snapshotDirectory: Optional directory to save snapshots. By default snapshots will be saved
///     in a directory with the same name as the test file, and that directory will sit inside a
///     directory `__Snapshots__` that sits next to your test file.
///   - timeout: The amount of time a snapshot must be generated in.
///   - file: The file in which failure occurred. Defaults to the file name of the test case in
///     which this function was called.
///   - testName: The name of the test in which failure occurred. Defaults to the function name of
///     the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
/// - Returns: A failure message or, if the value matches, nil.
public func verifySnapshot<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  record: SnapshotTestingConfiguration.Record? = nil,
  snapshotDirectory: String? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #file,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) -> String? {
  #if canImport(Testing)
    if Test.current == nil {
      CleanCounterBetweenTestCases.registerIfNeeded()
    }
  #else
    CleanCounterBetweenTestCases.registerIfNeeded()
  #endif

  let record = record ?? SnapshotTestingConfiguration.current?.record ?? _record
  return withSnapshotTesting(record: record) { () -> String? in
    do {
      let paths = try snapshotFilePaths(
        named: name,
        snapshotDirectory: snapshotDirectory,
        pathExtension: snapshotting.pathExtension,
        filePath: filePath,
        testName: testName
      )

      let tookSnapshot = XCTestExpectation(description: "Took snapshot")
      var optionalDiffable: Format?
      snapshotting.snapshot(try value()).run { b in
        optionalDiffable = b
        tookSnapshot.fulfill()
      }
      let result = XCTWaiter.wait(for: [tookSnapshot], timeout: timeout)
      switch result {
      case .completed:
        break
      case .timedOut:
        return timeoutFailureMessage(timeout: timeout)
      case .incorrectOrder, .invertedFulfillment, .interrupted:
        return "Couldn't snapshot value"
      @unknown default:
        return "Couldn't snapshot value"
      }

      guard let diffable = optionalDiffable else {
        return "Couldn't snapshot value"
      }

      return try compareSnapshot(
        of: diffable,
        as: snapshotting,
        named: name,
        record: record,
        paths: paths,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
    } catch {
      return error.localizedDescription
    }
  }
}

/// Verifies that a given value matches a reference on disk, suspending while the snapshot is
/// generated instead of blocking the current thread.
///
/// This overload works just like
/// ``verifySnapshot(of:as:named:record:snapshotDirectory:timeout:fileID:file:testName:line:column:)``,
/// except it uses Swift concurrency to wait for the snapshot to be generated, leaving the main
/// thread free to make progress on the work the snapshot strategy may be waiting on.
///
/// The snapshot operation is started before this function's first suspension point. A strategy
/// that produces its value synchronously (like an image snapshot of an already-rendered view)
/// therefore captures in the same run-loop iteration as the caller — exactly what the
/// synchronous overload captures — and no main-queue work, timer, or CoreAnimation commit can
/// mutate the value first. Only the wait for asynchronously produced values suspends.
///
/// - Parameters:
///   - value: A value to compare against a reference.
///   - snapshotting: A strategy for serializing, deserializing, and comparing values.
///   - name: An optional description of the snapshot.
///   - record: The record mode to use while asserting snapshots.
///   - snapshotDirectory: Optional directory to save snapshots. By default snapshots will be saved
///     in a directory with the same name as the test file, and that directory will sit inside a
///     directory `__Snapshots__` that sits next to your test file.
///   - timeout: The amount of time a snapshot must be generated in.
///   - fileID: The file ID in which failure occurred. Defaults to the file ID of the test case in
///     which this function was called.
///   - file: The file in which failure occurred. Defaults to the file name of the test case in
///     which this function was called.
///   - testName: The name of the test in which failure occurred. Defaults to the function name of
///     the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
///   - column: The column on which failure occurred. Defaults to the column on which this
///     function was called.
/// - Returns: A failure message or, if the value matches, nil.
@MainActor
public func verifySnapshot<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  record: SnapshotTestingConfiguration.Record? = nil,
  snapshotDirectory: String? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #file,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async -> String? {
  // Start the snapshot operation before the first suspension point. Strategies that produce
  // their value synchronously (like image snapshots of views that have already rendered)
  // capture the value here, in the same run-loop iteration as the caller — the same semantics
  // as the synchronous overload. Suspending first would let the main run loop turn (committing
  // CoreAnimation transactions, firing timers, and draining queued main-queue work) before the
  // value is captured, changing what gets snapshotted.
  let snapshot: EagerSnapshot<Format>
  do {
    snapshot = EagerSnapshot(snapshotting.snapshot(try value()))
  } catch {
    return error.localizedDescription
  }

  return await verifySnapshot(
    eager: snapshot,
    as: snapshotting,
    named: name,
    record: record,
    snapshotDirectory: snapshotDirectory,
    timeout: timeout,
    fileID: fileID,
    filePath: filePath,
    testName: testName,
    line: line,
    column: column
  )
}

/// Verifies an already-started snapshot operation against a reference on disk.
///
/// This is the shared back end of every async assertion: the caller starts the snapshot
/// operation synchronously (before any suspension point) by constructing an ``EagerSnapshot``,
/// and this function awaits its value and compares it against the reference.
@MainActor
private func verifySnapshot<Value, Format>(
  eager snapshot: EagerSnapshot<Format>,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String?,
  record: SnapshotTestingConfiguration.Record?,
  snapshotDirectory: String?,
  timeout: TimeInterval,
  fileID: StaticString,
  filePath: StaticString,
  testName: String,
  line: UInt,
  column: UInt
) async -> String? {
  #if canImport(Testing)
    if Test.current == nil {
      CleanCounterBetweenTestCases.registerIfNeeded()
    }
  #else
    CleanCounterBetweenTestCases.registerIfNeeded()
  #endif

  let record = record ?? SnapshotTestingConfiguration.current?.record ?? _record

  return await withSnapshotTesting(record: record) { () async -> String? in
    do {
      let paths = try snapshotFilePaths(
        named: name,
        snapshotDirectory: snapshotDirectory,
        pathExtension: snapshotting.pathExtension,
        filePath: filePath,
        testName: testName
      )

      guard let diffable = await snapshot.value(timeout: timeout)
      else {
        return timeoutFailureMessage(timeout: timeout)
      }

      return try compareSnapshot(
        of: diffable,
        as: snapshotting,
        named: name,
        record: record,
        paths: paths,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
    } catch {
      return error.localizedDescription
    }
  }
}

// MARK: - Private

/// Runs a snapshot operation as soon as it is initialized and supports awaiting its value later.
///
/// Initializing this class starts the operation synchronously, so a strategy that produces its
/// value without waiting (like an image snapshot of an already-rendered view) completes before
/// the initializer returns, and awaiting ``value(timeout:)`` returns it without suspending.
///
/// The timeout is enforced by a timer on a background queue so that snapshot work occupying the
/// main thread cannot delay the timeout indefinitely. If the timeout fires first,
/// ``value(timeout:)`` returns `nil` and a subsequently produced value is discarded.
private final class EagerSnapshot<Format>: @unchecked Sendable {
  private let lock = NSLock()
  private var state = State.inFlight

  private enum State {
    case inFlight
    case awaited(CheckedContinuation<Format?, Never>)
    case settled(Format?)
  }

  init(_ snapshot: Async<Format>) {
    snapshot.run { value in
      self.settle(with: value)
    }
  }

  func value(timeout: TimeInterval) async -> Format? {
    await withCheckedContinuation { continuation in
      let settled: Format??
      lock.lock()
      switch state {
      case .inFlight:
        state = .awaited(continuation)
        settled = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
          self.settle(with: nil)
        }
      case .awaited:
        fatalError("An EagerSnapshot's value may only be awaited once")
      case .settled(let value):
        settled = .some(value)
      }
      lock.unlock()
      if case .some(let value) = settled {
        continuation.resume(returning: value)
      }
    }
  }

  private func settle(with value: Format?) {
    lock.lock()
    switch state {
    case .inFlight:
      state = .settled(value)
      lock.unlock()
    case .awaited(let continuation):
      state = .settled(value)
      lock.unlock()
      continuation.resume(returning: value)
    case .settled:
      lock.unlock()
    }
  }
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
    // When running tests on Android, the CI script copies the Tests/SnapshotTestingTests/__Snapshots__ up to the temporary folder
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

/// Compares a snapshotted value against the reference on disk, recording a new reference when
/// the record mode calls for it.
///
/// This must be called within a `withSnapshotTesting` scope.
private func compareSnapshot<Value, Format>(
  of diffable: Format,
  as snapshotting: Snapshotting<Value, Format>,
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

  func recordSnapshot(writeToDisk: Bool) throws {
    let snapshotData = snapshotting.diffing.toData(diffable)

    if writeToDisk {
      try snapshotData.write(to: snapshotFileUrl)
    }

    #if !os(Android) && !os(Linux) && !os(Windows)
      if ProcessInfo.processInfo.environment.keys.contains("__XCODE_BUILT_PRODUCTS_DIR_PATHS") {
        if isSwiftTesting {
          #if compiler(>=6.2)
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
              // Snapshot was written to disk. Create attachment from file
              let attachment = XCTAttachment(contentsOfFile: snapshotFileUrl)
              activity.add(attachment)
            } else {
              // Snapshot was not written to disk. Create attachment from data and path extension
              let typeIdentifier = snapshotting.pathExtension.flatMap(
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
  let reference = snapshotting.diffing.fromData(data)

  #if os(iOS) || os(tvOS)
    // If the image generation fails for the diffable part and the reference was empty, use the reference
    if let localDiff = diffable as? UIImage,
      let refImage = reference as? UIImage,
      localDiff.size == .zero && refImage.size == .zero
    {
      diffable = reference
    }
  #endif

  guard let (failure, attachments) = snapshotting.diffing.diffV2(reference, diffable) else {
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
  try snapshotting.diffing.toData(diffable).write(to: failedSnapshotFileUrl)

  if !attachments.isEmpty {
    #if !os(Linux) && !os(Android) && !os(Windows)
      if ProcessInfo.processInfo.environment.keys.contains("__XCODE_BUILT_PRODUCTS_DIR_PATHS") {
        if isSwiftTesting {
          #if compiler(>=6.2)
            attachments.forEach {
              switch $0 {
              case .xcTest:
                break
              case .data(let data, let name):
                recordSwiftTestingAttachment(
                  data,
                  named: name,
                  sourceLocation: SourceLocation(
                    fileID: fileID.description,
                    filePath: filePath.description,
                    line: Int(line),
                    column: Int(column)
                  )
                )
              }
            }
          #endif
        } else {
          XCTContext.runActivity(named: "Attached Failure Diff") { activity in
            attachments.forEach {
              switch $0 {
              case .xcTest(let attachment):
                activity.add(attachment)
              case .data(let data, let name):
                let attachment = XCTAttachment(data: data)
                attachment.name = name
                activity.add(attachment)
                break
              }
            }
          }
        }
      }
    #endif
  }

  let diffMessage = (SnapshotTestingConfiguration.current?.diffTool ?? _diffTool)(
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

    \(failure.trimmingCharacters(in: .whitespacesAndNewlines))
    """
}

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

func sanitizePathComponent(_ string: String) -> String {
  return
    string
    .replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
    .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
}

#if !os(Android) && !os(Linux) && !os(Windows)
  import CoreServices

  func uniformTypeIdentifier(fromExtension pathExtension: String) -> String? {
    // This can be much cleaner in macOS 11+ using UTType
    let unmanagedString = UTTypeCreatePreferredIdentifierForTag(
      kUTTagClassFilenameExtension as CFString,
      pathExtension as CFString,
      nil
    )

    return unmanagedString?.takeRetainedValue() as String?
  }
#endif

// We need to clean counter between tests executions in order to support test-iterations.
private class CleanCounterBetweenTestCases: NSObject, XCTestObservation {
  private static var registered = false

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
      return counts[key]!
    }

    func reset() {
      lock.lock()
      defer { lock.unlock() }
      counts.removeAll()
    }
  }
}

#if canImport(Testing) && compiler(>=6.2)
  private func recordSwiftTestingAttachment(
    _ data: Data,
    named name: String,
    sourceLocation: SourceLocation
  ) {
    #if !os(Android) && !os(Linux) && !os(Windows)
      #if compiler(>=6.3) && (canImport(UIKit) || canImport(AppKit))
        if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *),
          name.hasSuffix(".png"),
          let image = Image(data: data)
        {
          Attachment.record(image, named: name, as: .png, sourceLocation: sourceLocation)
          return
        }
      #endif
      Attachment.record(data, named: name, sourceLocation: sourceLocation)
    #endif
  }
#endif
