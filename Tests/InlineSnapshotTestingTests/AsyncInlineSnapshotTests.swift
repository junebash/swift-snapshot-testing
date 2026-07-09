import Foundation
import InlineSnapshotTesting
import SnapshotTesting
import XCTest

/// Coverage for the async `assertInlineSnapshot` overload, which captures through the
/// protocol-based `SnapshotStrategy` engine while sharing the inline source-rewriting machinery
/// with the legacy overload.
final class AsyncInlineSnapshotTests: BaseTestCase {
  @MainActor
  func testAsyncInlineSnapshot() async {
    await assertInlineSnapshot(of: ["Hello", "World"], as: .dump()) {
      """
      ▿ 2 elements
        - "Hello"
        - "World"

      """
    }
  }

  @MainActor
  func testAsyncInlineSnapshot_NamedTrailingClosure() async {
    await assertInlineSnapshot(
      of: "Hello\nWorld", as: .lines,
      matches: {
        """
        Hello
        World
        """
      })
  }
}
