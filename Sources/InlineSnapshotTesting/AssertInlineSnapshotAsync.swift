import Foundation

#if canImport(SwiftSyntax509)
  import SnapshotTestingAsync
  import SwiftParser
  import SwiftSyntax
  import SwiftSyntaxBuilder

  /// Asserts that a given value matches an inline string snapshot, capturing it through the
  /// async, protocol-based engine.
  ///
  /// The inline machinery (source rewriting, test observers, failure formatting) is shared with
  /// the legacy overload; only the capture and diff go through `SnapshotStrategy`. Like
  /// `assertSnapshot`, the capture's synchronous prefix runs eagerly on the caller's main-actor
  /// turn, and the timeout applies only at genuine suspension points.
  ///
  /// See <doc:InlineSnapshotTesting> for more info.
  ///
  /// - Parameters:
  ///   - value: A value to compare against a snapshot.
  ///   - strategy: A strategy for snapshotting and comparing values.
  ///   - message: An optional description of the assertion, for inclusion in test results.
  ///   - record: Whether or not to record a new reference.
  ///   - timeout: The amount of time an asynchronously produced snapshot must be generated in.
  ///   - syntaxDescriptor: An optional description of where the snapshot is inlined. This
  ///     parameter should be omitted unless you are writing a custom helper that calls this
  ///     function under the hood. See ``InlineSnapshotSyntaxDescriptor`` for more.
  ///   - expected: An optional closure that returns a previously generated snapshot. When
  ///     omitted, the library will automatically write a snapshot into your test file at the call
  ///     site of the assertion.
  ///   - fileID: The file ID in which failure occurred.
  ///   - filePath: The file in which failure occurred.
  ///   - function: The function where the assertion occurs.
  ///   - line: The line number on which failure occurred.
  ///   - column: The column on which failure occurred.
  @MainActor
  public func assertInlineSnapshot<S: SnapshotStrategy>(
    of value: @autoclosure () throws -> S.Value?,
    as strategy: S,
    message: @autoclosure () -> String = "",
    record: SnapshotTestingAsync.SnapshotTestingConfiguration.Record? = nil,
    timeout: TimeInterval = 5,
    syntaxDescriptor: InlineSnapshotSyntaxDescriptor = InlineSnapshotSyntaxDescriptor(),
    matches expected: (() -> String)? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column
  ) async where S.Format == String {
    await SnapshotTestingAsync.withSnapshotTesting(record: record) {
      // `withSnapshotTesting` resolved the full fallback chain into the task-local.
      let record = SnapshotTestingAsync.SnapshotTestingConfiguration.current?.record ?? .missing
      let _: Void = installTestObserver
      do {
        var actual: String?
        if let value = try value() {
          let capture = SnapshotCaptureContext(timeout: timeout)
          actual = await SnapshotCaptureContext.$current.withValue(capture) {
            await strategy.snapshot(of: value)
          }
          if capture.timedOut {
            recordIssue(
              """
              Exceeded timeout of \(timeout) seconds waiting for snapshot.

              This can happen when an asynchronously loaded value (like a network response) has not \
              loaded. If a timeout is unavoidable, consider setting the "timeout" parameter of
              "assertInlineSnapshot" to a higher value.
              """,
              fileID: fileID,
              filePath: filePath,
              line: line,
              column: column
            )
            return
          }
        }
        let expected = expected?()
        func recordSnapshot() {
          // NB: Write snapshot state before failing in case `continueAfterFailure = false`
          inlineSnapshotState.withLock { [actual] in
            $0[File(path: filePath), default: []].append(
              InlineSnapshot(
                expected: expected,
                actual: actual,
                wasRecording: record == .all || record == .failed,
                syntaxDescriptor: syntaxDescriptor,
                function: "\(function)",
                line: line,
                column: column
              )
            )
          }
        }
        guard
          record != .all,
          (record != .missing && record != .failed) || expected != nil
        else {
          recordSnapshot()

          var failure: String
          if syntaxDescriptor.trailingClosureLabel
            == InlineSnapshotSyntaxDescriptor.defaultTrailingClosureLabel
          {
            failure = "Automatically recorded a new snapshot."
          } else {
            failure = """
              Automatically recorded a new snapshot for "\(syntaxDescriptor.trailingClosureLabel)".
              """
          }
          if let difference = strategy.diffing.diff(expected ?? "", actual ?? "")?.message {
            failure += " Difference: …\n\n\(difference.indenting(by: 2))"
          }
          recordIssue(
            """
            \(failure)

            Re-run "\(function)" to assert against the newly-recorded snapshot.
            """,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
          )
          return
        }

        guard let expected
        else {
          recordIssue(
            """
            No expected value to assert against.
            """,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
          )
          return
        }
        guard
          let difference = strategy.diffing.diff(expected, actual ?? "")?.message
        else { return }

        let message = message()
        var failureMessage = """
          \(message.isEmpty ? "Snapshot did not match. Difference: …" : message)

          \(difference.indenting(by: 2))
          """

        if record == .failed {
          recordSnapshot()
          failureMessage += "\n\nA new snapshot was automatically recorded."
        }

        syntaxDescriptor.fail(
          failureMessage,
          fileID: fileID,
          file: filePath,
          line: line,
          column: column
        )
      } catch {
        recordIssue(
          "Threw error: \(error)",
          fileID: fileID,
          filePath: filePath,
          line: line,
          column: column
        )
      }
    }
  }
#endif
