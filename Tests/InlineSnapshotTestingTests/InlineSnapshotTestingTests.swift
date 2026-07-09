import Foundation
@_spi(Internals) import InlineSnapshotTesting
import SnapshotTesting
import XCTest

final class InlineSnapshotTestingTests: BaseTestCase {
  @MainActor
  func testInlineSnapshot() async {
    await assertInlineSnapshot(of: ["Hello", "World"], as: .dump()) {
      """
      ▿ 2 elements
        - "Hello"
        - "World"

      """
    }
  }

  @MainActor
  func testInlineSnapshot_NamedTrailingClosure() async {
    await assertInlineSnapshot(
      of: ["Hello", "World"], as: .dump(),
      matches: {
        """
        ▿ 2 elements
          - "Hello"
          - "World"

        """
      })
  }

  @MainActor
  func testInlineSnapshot_Escaping() async {
    await assertInlineSnapshot(of: "Hello\"\"\"#, world", as: .lines) {
      ##"""
      Hello"""#, world
      """##
    }
  }

  @MainActor
  func testCustomInlineSnapshot() async {
    await assertCustomInlineSnapshot {
      "Hello"
    } is: {
      """
      - "Hello"

      """
    }
  }

  @MainActor
  func testCustomInlineSnapshot_Multiline() async {
    await assertCustomInlineSnapshot {
      """
      "Hello"
      "World"
      """
    } is: {
      #"""
      - "\"Hello\"\n\"World\""

      """#
    }
  }

  @MainActor
  func testCustomInlineSnapshot_SingleTrailingClosure() async {
    await assertCustomInlineSnapshot(of: { "Hello" }) {
      """
      - "Hello"

      """
    }
  }

  @MainActor
  func testCustomInlineSnapshot_MultilineSingleTrailingClosure() async {
    await assertCustomInlineSnapshot(
      of: { "Hello" }
    ) {
      """
      - "Hello"

      """
    }
  }

  @MainActor
  func testCustomInlineSnapshot_NoTrailingClosure() async {
    await assertCustomInlineSnapshot(
      of: { "Hello" },
      is: {
        """
        - "Hello"

        """
      }
    )
  }

  @MainActor
  func testArgumentlessInlineSnapshot() async {
    func assertArgumentlessInlineSnapshot(
      expected: (() -> String)? = nil,
      fileID: StaticString = #fileID,
      file filePath: StaticString = #filePath,
      function: StaticString = #function,
      line: UInt = #line,
      column: UInt = #column
    ) async {
      await assertInlineSnapshot(
        of: "Hello",
        as: .dump(),
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "is",
          trailingClosureOffset: 1
        ),
        matches: expected,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    }

    await assertArgumentlessInlineSnapshot {
      """
      - "Hello"

      """
    }
  }

  @MainActor
  func testMultipleInlineSnapshots() async {
    func assertResponse(
      of url: () -> String,
      head: (() -> String)? = nil,
      body: (() -> String)? = nil,
      fileID: StaticString = #fileID,
      file filePath: StaticString = #filePath,
      function: StaticString = #function,
      line: UInt = #line,
      column: UInt = #column
    ) async {
      await assertInlineSnapshot(
        of: """
          HTTP/1.1 200 OK
          Content-Type: text/html; charset=utf-8
          """,
        as: .lines,
        message: "Head did not match",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "head",
          trailingClosureOffset: 1
        ),
        matches: head,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
      await assertInlineSnapshot(
        of: """
          <!doctype html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <title>Point-Free</title>
            <link rel="stylesheet" href="style.css">
          </head>
          <body>
            <p>What's the point?</p>
          </body>
          </html>
          """,
        as: .lines,
        message: "Body did not match",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "body",
          trailingClosureOffset: 2
        ),
        matches: body,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    }

    await assertResponse {
      """
      https://www.pointfree.co/
      """
    } head: {
      """
      HTTP/1.1 200 OK
      Content-Type: text/html; charset=utf-8
      """
    } body: {
      """
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Point-Free</title>
        <link rel="stylesheet" href="style.css">
      </head>
      <body>
        <p>What's the point?</p>
      </body>
      </html>
      """
    }
  }

  @MainActor
  func testAsyncThrowing() async throws {
    func assertAsyncThrowingInlineSnapshot(
      of value: () -> String,
      is expected: (() -> String)? = nil,
      fileID: StaticString = #fileID,
      file filePath: StaticString = #filePath,
      function: StaticString = #function,
      line: UInt = #line,
      column: UInt = #column
    ) async throws {
      await assertInlineSnapshot(
        of: value(),
        as: .dump(),
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "is",
          trailingClosureOffset: 1
        ),
        matches: expected,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    }

    try await assertAsyncThrowingInlineSnapshot {
      "Hello"
    } is: {
      """
      - "Hello"

      """
    }
  }

  @MainActor
  func testNestedInClosureFunction() async {
    func withDependencies(operation: () async -> Void) async {
      await operation()
    }

    await withDependencies {
      await assertInlineSnapshot(of: "Hello", as: .dump()) {
        """
        - "Hello"

        """
      }
    }
  }

  @MainActor
  func testCarriageReturnInlineSnapshot() async {
    await assertInlineSnapshot(of: "This is a line\r\nAnd this is a line\r\n", as: .lines) {
      """
      This is a line\r
      And this is a line\r

      """
    }
  }

  @MainActor
  func testCarriageReturnRawInlineSnapshot() async {
    await assertInlineSnapshot(of: "\"\"\"#This is a line\r\nAnd this is a line\r\n", as: .lines) {
      ##"""
      """#This is a line\##r
      And this is a line\##r

      """##
    }
  }

  #if canImport(Darwin)
    @MainActor
    func testRecordFailed_IncorrectExpectation() async throws {
      let initialInlineSnapshotState = inlineSnapshotState.withLock { $0 }
      defer { inlineSnapshotState.withLock { $0 = initialInlineSnapshotState } }

      XCTExpectFailure {
        $0.compactDescription == """
          failed - Snapshot did not match. Difference: …

            @@ −1,1 +1,1 @@
            −4
            +42

          A new snapshot was automatically recorded.
          """
      }
      await withSnapshotTesting(record: .failed) {
        await assertInlineSnapshot(of: 42, as: .json()) {
          """
          4
          """
        }
      }

      inlineSnapshotState.withLock { inlineSnapshotState in
        XCTAssertEqual(inlineSnapshotState.count, 1)
        XCTAssertEqual(
          String(describing: inlineSnapshotState.keys.first!.path)
            .hasSuffix("InlineSnapshotTestingTests.swift"),
          true
        )
      }
    }
  #endif

  #if canImport(Darwin)
    @MainActor
    func testRecordFailed_MissingExpectation() async throws {
      let initialInlineSnapshotState = inlineSnapshotState.withLock { $0 }
      defer { inlineSnapshotState.withLock { $0 = initialInlineSnapshotState } }

      XCTExpectFailure {
        $0.compactDescription == """
          failed - Automatically recorded a new snapshot. Difference: …

            @@ −1,1 +1,1 @@
            −
            +42

          Re-run "testRecordFailed_MissingExpectation()" to assert against the newly-recorded snapshot.
          """
      }
      await withSnapshotTesting(record: .failed) {
        await assertInlineSnapshot(of: 42, as: .json())
      }

      inlineSnapshotState.withLock { inlineSnapshotState in
        XCTAssertEqual(inlineSnapshotState.count, 1)
        XCTAssertEqual(
          String(describing: inlineSnapshotState.keys.first!.path)
            .hasSuffix("InlineSnapshotTestingTests.swift"),
          true
        )
      }
    }
  #endif
}

@MainActor
private func assertCustomInlineSnapshot(
  of value: () -> String,
  is expected: (() -> String)? = nil,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) async {
  await assertInlineSnapshot(
    of: value(),
    as: .dump(),
    syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
      trailingClosureLabel: "is",
      trailingClosureOffset: 1
    ),
    matches: expected,
    fileID: fileID,
    file: filePath,
    function: function,
    line: line,
    column: column
  )
}
