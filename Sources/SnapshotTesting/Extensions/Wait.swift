import Foundation

extension Snapshotting {
  /// Transforms an existing snapshot strategy into one that waits for some amount of time before
  /// taking the snapshot. This can be useful for waiting for animations to complete or for UIKit
  /// events to finish (_i.e._ waiting for a `UINavigationController` to push a child onto the
  /// stack).
  ///
  /// The wait is scheduled on the main queue without blocking the thread that runs the strategy,
  /// so the main thread remains free to process the work being waited on.
  ///
  /// - Parameters:
  ///   - duration: The amount of time to wait before taking the snapshot.
  ///   - strategy: The snapshot to invoke after the specified amount of time has passed.
  public static func wait(
    for duration: TimeInterval,
    on strategy: Self
  ) -> Self {
    Self(
      pathExtension: strategy.pathExtension,
      diffing: strategy.diffing,
      asyncSnapshot: { value in
        Async { callback in
          DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            strategy.snapshot(value).run(callback)
          }
        }
      })
  }
}
