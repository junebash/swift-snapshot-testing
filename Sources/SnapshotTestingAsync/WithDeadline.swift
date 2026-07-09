import Foundation

/// Thrown by ``withDeadline(in:clock:operation:)`` when the operation does not complete in time.
public struct DeadlineExceededError: Error, Equatable {
  /// The deadline that was exceeded, measured from the call.
  public var duration: Duration
  public init(duration: Duration) {
    self.duration = duration
  }
}

/// Carries a possibly-non-`Sendable` value across the task-group boundary.
///
/// Safe here because the value is produced and consumed on the same executor (the assertion's
/// `@MainActor`); the box only moves the reference through the group's `Sendable`-constrained
/// result channel. This mirrors the old `EagerSnapshot`'s `@unchecked Sendable`.
private struct UncheckedSendable<Wrapped>: @unchecked Sendable {
  var wrapped: Wrapped
}

/// Runs `operation`, cancelling it and throwing ``DeadlineExceededError`` if it does not finish
/// within `duration`.
///
/// Modeled on the pitched standard-library `withDeadline` (SE-0526): the operation races a
/// monotonic `ContinuousClock` timer in a task group; whichever finishes first wins and the loser
/// is cancelled.
///
/// - Important: Cancellation is **cooperative**. An operation that never observes
///   `Task.isCancelled` — such as a synchronous image render — can outlive the deadline. The timer
///   still fires and the caller still gets ``DeadlineExceededError``, but the operation's own work
///   continues in the background until it returns. This matches how the old timeout ran its timer on
///   a background queue so main-thread render work could not starve it.
///
/// The result is `sending` and is laundered across the group boundary, so a non-`Sendable` format
/// (e.g. `NSImage`) can flow back to the caller.
nonisolated(nonsending)
public func withDeadline<Result>(
  in duration: Duration,
  clock: ContinuousClock = ContinuousClock(),
  operation: @escaping @Sendable () async -> sending Result
) async throws -> sending Result {
  let boxed = try await withThrowingTaskGroup(
    of: UncheckedSendable<Result>.self
  ) { group in
    group.addTask {
      UncheckedSendable(wrapped: await operation())
    }
    group.addTask {
      try await Task.sleep(for: duration, clock: clock)
      throw DeadlineExceededError(duration: duration)
    }
    defer { group.cancelAll() }
    guard let first = try await group.next() else {
      throw CancellationError()
    }
    return first
  }
  return boxed.wrapped
}
