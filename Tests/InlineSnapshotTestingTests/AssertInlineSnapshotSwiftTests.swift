#if canImport(Testing)
  import Testing
  import Foundation
  import InlineSnapshotTesting
  import SnapshotTesting

  extension BaseSuite {
    @Suite
    @MainActor
    struct AssertInlineSnapshotTests {
      @Test func inlineSnapshot() async {
        await assertInlineSnapshot(of: ["Hello", "World"], as: .dump()) {
          """
          ▿ 2 elements
            - "Hello"
            - "World"

          """
        }
      }

      @Test(.snapshots(record: .missing))
      func inlineSnapshotFailure() async {
        await withKnownIssue {
          await assertInlineSnapshot(of: ["Hello", "World"], as: .dump()) {
            """
            ▿ 2 elements
              - "Hello"

            """
          }
        } matching: { issue in
          // Context lines in diff hunks are marked with U+2007 (figure space), written as an
          // explicit escape so editors can't silently normalize it to a plain space. `contains`,
          // not `hasSuffix`, because the diff ends with a whitespace-only context line that's
          // just as prone to being stripped.
          issue.description.contains(
            """
            Snapshot did not match. Difference: …

              @@ −1,3 +1,4 @@
              \u{2007}▿ 2 elements
              \u{2007}  - "Hello"
              +  - "World"
            """)
        }
      }

      @Test func inlineSnapshot_NamedTrailingClosure() async {
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

      @Test func inlineSnapshot_Escaping() async {
        await assertInlineSnapshot(of: "Hello\"\"\"#, world", as: .lines) {
          ##"""
          Hello"""#, world
          """##
        }
      }

      @Test func customInlineSnapshot() async {
        await assertCustomInlineSnapshot {
          "Hello"
        } is: {
          """
          - "Hello"

          """
        }
      }

      @Test func customInlineSnapshot_Multiline() async {
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

      @Test func customInlineSnapshot_SingleTrailingClosure() async {
        await assertCustomInlineSnapshot(of: { "Hello" }) {
          """
          - "Hello"

          """
        }
      }

      @Test func customInlineSnapshot_MultilineSingleTrailingClosure() async {
        await assertCustomInlineSnapshot(
          of: { "Hello" }
        ) {
          """
          - "Hello"

          """
        }
      }

      @Test func customInlineSnapshot_NoTrailingClosure() async {
        await assertCustomInlineSnapshot(
          of: { "Hello" },
          is: {
            """
            - "Hello"

            """
          }
        )
      }

      @Test func argumentlessInlineSnapshot() async {
        func assertArgumentlessInlineSnapshot(
          expected: (() -> String)? = nil,
          fileID: StaticString = #fileID,
          filePath: StaticString = #filePath,
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

      @Test func multipleInlineSnapshots() async {
        func assertResponse(
          of url: () -> String,
          head: (() -> String)? = nil,
          body: (() -> String)? = nil,
          fileID: StaticString = #fileID,
          filePath: StaticString = #filePath,
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

      @Test func asyncThrowing() async throws {
        func assertAsyncThrowingInlineSnapshot(
          of value: () -> String,
          is expected: (() -> String)? = nil,
          fileID: StaticString = #fileID,
          filePath: StaticString = #filePath,
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

      @Test func nestedInClosureFunction() async {
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

      @Test func carriageReturnInlineSnapshot() async {
        await assertInlineSnapshot(of: "This is a line\r\nAnd this is a line\r\n", as: .lines) {
          """
          This is a line\r
          And this is a line\r

          """
        }
      }

      @Test func carriageReturnRawInlineSnapshot() async {
        await assertInlineSnapshot(of: "\"\"\"#This is a line\r\nAnd this is a line\r\n", as: .lines) {
          ##"""
          """#This is a line\##r
          And this is a line\##r

          """##
        }
      }
    }
  }

  @MainActor
  private func assertCustomInlineSnapshot(
    of value: () -> String,
    is expected: (() -> String)? = nil,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
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

#endif
