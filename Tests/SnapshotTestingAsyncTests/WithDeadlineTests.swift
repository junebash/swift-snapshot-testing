import Foundation
import Testing

@testable import SnapshotTestingAsync

@Suite struct WithDeadlineTests {
  @Test func returnsOperationResultWhenFast() async throws {
    let value = try await withDeadline(in: .seconds(10)) {
      "captured"
    }
    #expect(value == "captured")
  }

  @Test func throwsWhenOperationExceedsDeadline() async {
    await #expect(throws: DeadlineExceededError.self) {
      try await withDeadline(in: .milliseconds(20)) {
        try? await Task.sleep(for: .seconds(10))
        return "never"
      }
    }
  }

  /// The advisor's timeout-executor check: the deadline timer must fire even while a `@MainActor`
  /// operation is suspended mid-flight, so main-thread render work can't starve the timeout.
  @Test @MainActor func timerFiresWhileMainActorOperationInFlight() async {
    let start = ContinuousClock().now
    await #expect(throws: DeadlineExceededError.self) {
      try await withDeadline(in: .milliseconds(50)) { @MainActor in
        // A main-actor operation that suspends (as a genuinely-async view render would).
        try? await Task.sleep(for: .seconds(10))
        return 0
      }
    }
    let elapsed = ContinuousClock().now - start
    // Should time out promptly, not wait the full 10s.
    #expect(elapsed < .seconds(1))
  }

  /// A non-`Sendable` result must be able to flow back out through the deadline's task group.
  @Test func carriesNonSendableResult() async throws {
    final class NotSendable { let id = 42 }
    let result = try await withDeadline(in: .seconds(10)) {
      NotSendable()
    }
    #expect(result.id == 42)
  }
}
